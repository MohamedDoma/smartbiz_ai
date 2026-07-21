<?php

namespace App\Console\Commands;

use App\Mail\TrialEndingMail;
use App\Models\WorkspaceSubscription;
use App\Services\Email\EmailService;
use App\Services\WorkspaceContextManager;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SendTrialEndingEmails extends Command
{
    protected $signature = 'email:send-trial-ending';
    protected $description = 'Send trial-ending warning emails (with dedup)';

    public function handle(EmailService $emailService, WorkspaceContextManager $workspaceContext): int
    {
        $expiring = WorkspaceSubscription::where('status', 'trial')
            ->whereBetween('trial_ends_at', [now(), now()->addDays(3)])
            ->get();

        $sent = 0;
        foreach ($expiring as $subscription) {
            $workspace = DB::table('workspaces')->where('id', $subscription->workspace_id)->first();
            $owner = $this->getOwnerEmail($subscription->workspace_id);

            if (! $owner) {
                continue;
            }

            $daysRemaining = (int) now()->diffInDays($subscription->trial_ends_at, false);
            $logId = $workspaceContext->runSystemInWorkspace(
                $subscription->workspace_id,
                fn (): ?string => $emailService->send(
                    $subscription->workspace_id,
                    $owner->email,
                    $owner->name ?? 'User',
                    new TrialEndingMail(
                        $workspace->name ?? 'Your Workspace',
                        max($daysRemaining, 0),
                    ),
                    'trial_ending',
                    [
                        'event_name' => 'scheduled:trial_ending',
                        'related_entity_type' => 'subscription',
                        'related_entity_id' => $subscription->id,
                    ],
                ),
            );

            if ($logId) {
                $sent++;
            }
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
