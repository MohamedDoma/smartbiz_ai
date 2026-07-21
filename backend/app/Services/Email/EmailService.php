<?php

namespace App\Services\Email;

use Illuminate\Contracts\Mail\Mailable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

/**
 * Central email gateway.
 *
 * All outbound emails MUST go through this service.
 * Features: send/queue, logging, retry, dedup, global/workspace toggles.
 */
class EmailService
{
    public function __construct(
        private readonly EmailConfigService $config,
    ) {}

    /**
     * Send an email immediately.
     *
     * @param  string       $workspaceId
     * @param  string       $recipientEmail
     * @param  string       $recipientName
     * @param  Mailable     $mailable
     * @param  string       $template       Template key (e.g. 'invoice_created')
     * @param  array        $meta           Extra log metadata
     * @return string|null  Email log ID, or null if skipped
     */
    public function send(
        string   $workspaceId,
        string   $recipientEmail,
        string   $recipientName,
        Mailable $mailable,
        string   $template,
        array    $meta = [],
    ): ?string {
        return $this->dispatch($workspaceId, $recipientEmail, $recipientName, $mailable, $template, 'immediate', $meta);
    }

    /**
     * Queue an email for async delivery.
     */
    public function queue(
        string   $workspaceId,
        string   $recipientEmail,
        string   $recipientName,
        Mailable $mailable,
        string   $template,
        array    $meta = [],
    ): ?string {
        return $this->dispatch($workspaceId, $recipientEmail, $recipientName, $mailable, $template, 'queued', $meta);
    }

    /**
     * Retry a failed email log entry.
     */
    public function retry(string $logId): bool
    {
        $log = DB::table('email_logs')->where('id', $logId)->first();
        if (! $log || $log->status !== 'failed') {
            return false;
        }

        if ($log->retries >= $log->max_retries) {
            return false;
        }

        DB::table('email_logs')->where('id', $logId)->update([
            'status'        => 'retrying',
            'delivery_mode' => 'retry',
            'retries'       => $log->retries + 1,
        ]);

        // Re-render from metadata isn't practical — mark as retrying and call Mail with stored info
        try {
            // For retry, we send a simple text email with stored subject
            Mail::raw('This is a retry of a previously failed email.', function ($msg) use ($log) {
                $msg->to($log->recipient_email, $log->recipient_name)
                    ->subject('[Retry] ' . $log->subject);
            });

            DB::table('email_logs')->where('id', $logId)->update([
                'status'  => 'sent',
                'sent_at' => now(),
            ]);
            return true;
        } catch (\Throwable $e) {
            DB::table('email_logs')->where('id', $logId)->update([
                'status'        => 'failed',
                'error_message' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Retry all failed emails that haven't exceeded max_retries.
     */
    public function retryAllFailed(): int
    {
        return $this->retryFailedQuery(
            DB::table('email_logs')
                ->where('status', 'failed')
                ->whereRaw('retries < max_retries'),
        );
    }

    public function retryAllFailedForWorkspace(string $workspaceId): int
    {
        return $this->retryFailedQuery(
            DB::table('email_logs')
                ->where('workspace_id', $workspaceId)
                ->where('status', 'failed')
                ->whereRaw('retries < max_retries'),
        );
    }

    private function retryFailedQuery($query): int
    {
        $failed = $query->limit(50)->get();

        $retried = 0;
        foreach ($failed as $log) {
            if ($this->retry($log->id)) {
                $retried++;
            }
        }

        return $retried;
    }

    // ── Core ────────────────────────────────────────────

    private function dispatch(
        string   $workspaceId,
        string   $recipientEmail,
        string   $recipientName,
        Mailable $mailable,
        string   $template,
        string   $deliveryMode,
        array    $meta,
    ): ?string {
        // 1. Check global + workspace toggle
        if (! $this->config->isEnabledForWorkspace($workspaceId)) {
            Log::info("Email skipped: disabled for workspace {$workspaceId}", ['template' => $template]);
            return null;
        }

        // 2. Check daily limit
        if (! $this->config->isWithinDailyLimit($workspaceId)) {
            Log::warning("Email skipped: daily limit exceeded for workspace {$workspaceId}");
            return null;
        }

        // 3. Build dedup key (for event-driven emails)
        $dedupKey = null;
        if (! empty($meta['related_entity_type']) && ! empty($meta['related_entity_id'])) {
            $dedupKey = implode(':', [
                $template,
                $meta['related_entity_type'],
                $meta['related_entity_id'],
                now()->toDateString(),
            ]);

            // Check dedup — if exists, skip
            $exists = DB::table('email_logs')
                ->where('workspace_id', $workspaceId)
                ->where('dedup_key', $dedupKey)
                ->exists();

            if ($exists) {
                Log::info("Email deduped: {$dedupKey}");
                return null;
            }
        }

        // 4. Apply sender info
        $sender = $this->config->getSenderInfo($workspaceId);
        $mailable->from($sender['from_email'], $sender['from_name']);
        if ($sender['reply_to']) {
            $mailable->replyTo($sender['reply_to']);
        }

        // 5. Determine subject from mailable
        // Build the mailable to extract the subject
        $subject = $mailable->envelope()->subject ?? $template;

        // 6. Create log entry
        $logId = Str::uuid()->toString();
        DB::table('email_logs')->insert([
            'id'                  => $logId,
            'workspace_id'        => $workspaceId,
            'recipient_email'     => $recipientEmail,
            'recipient_name'      => $recipientName,
            'template'            => $template,
            'template_version'    => $meta['template_version'] ?? 'v1',
            'subject'             => $subject,
            'status'              => 'sending',
            'delivery_mode'       => $deliveryMode,
            'mailer_provider'     => config('mail.default', 'smtp'),
            'actor_user_id'       => $meta['actor_user_id'] ?? null,
            'event_name'          => $meta['event_name'] ?? null,
            'correlation_key'     => $meta['correlation_key'] ?? null,
            'related_entity_type' => $meta['related_entity_type'] ?? null,
            'related_entity_id'   => $meta['related_entity_id'] ?? null,
            'dedup_key'           => $dedupKey,
            'metadata'            => json_encode($meta['extra'] ?? []),
            'created_at'          => now(),
        ]);

        // 7. Send or queue
        try {
            // Resend's onboarding sandbox only accepts the exact account
            // email address and rejects a named recipient address.
            $pendingMail = $this->usesResendSandbox($sender['from_email'])
                ? Mail::to($recipientEmail)
                : Mail::to($recipientEmail, $recipientName);

            if ($deliveryMode === 'queued' && $mailable instanceof \Illuminate\Contracts\Queue\ShouldQueue) {
                $pendingMail->queue($mailable);
            } else {
                $pendingMail->send($mailable);
            }

            DB::table('email_logs')->where('id', $logId)->update([
                'status'  => 'sent',
                'sent_at' => now(),
            ]);

            return $logId;
        } catch (\Throwable $e) {
            Log::error("Email send failed: {$e->getMessage()}", [
                'template' => $template,
                'recipient' => $recipientEmail,
            ]);

            DB::table('email_logs')->where('id', $logId)->update([
                'status'        => 'failed',
                'error_message' => substr($e->getMessage(), 0, 1000),
            ]);

            return $logId;
        }
    }

    /**
     * The Resend testing sender requires an exact bare recipient address.
     * A verified production domain can continue using recipient display names.
     */
    private function usesResendSandbox(string $fromEmail): bool
    {
        return config('mail.default') === 'resend'
            && strcasecmp(trim($fromEmail), 'onboarding@resend.dev') === 0;
    }

}
