<?php

namespace App\Console\Commands;

use App\Mail\TrialEndingMail;
use App\Models\WorkspaceSubscription;
use App\Services\Email\EmailService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SendTrialEndingEmails extends Command
{
    protected $signature = 'email:send-trial-ending';
    protected $description = 'Send trial-ending warning emails (with dedup)';

    public function handle(EmailService $emailService): int
    {
        $expiring = WorkspaceSubscription::where('status', 'trial')
            ->whereBetween('trial_ends_at', [now(), now()->addDays(3)])
            ->get();

        $sent = 0;
        foreach ($expiring as $sub) {
            $workspace = DB::table('workspaces')->where('id', $sub->workspace_id)->first();
            $owner     = $this->getOwnerEmail($sub->workspace_id);
            if (! $owner) continue;

            $daysRemaining = (int) now()->diffInDays($sub->trial_ends_at, false);

            $logId = $emailService->send(
                $sub->workspace_id,
                $owner->email,
                $owner->name ?? 'User',
                new TrialEndingMail(
                    $workspace->name ?? 'Your Workspace',
                    max($daysRemaining, 0),
                ),
                'trial_ending',
                [
                    'event_name'          => 'scheduled:trial_ending',
                    'related_entity_type' => 'subscription',
                    'related_entity_id'   => $sub->id,
                ],
            );

            if ($logId) $sent++;
        }

        $this->info("Trial ending emails sent: {$sent}");
        return self::SUCCESS;
    }

    private function getOwnerEmail(string $workspaceId): ?object
    {
        return DB::table('workspace_memberships')
            ->join('users', 'users.id', '=', 'workspace_memberships.user_id')
            ->where('workspace_memberships.workspace_id', $workspaceId)
            ->where('workspace_memberships.status', 'active')
            ->orderBy('workspace_memberships.created_at')
            ->select('users.email', 'users.full_name as name')
            ->first();
    }
}
