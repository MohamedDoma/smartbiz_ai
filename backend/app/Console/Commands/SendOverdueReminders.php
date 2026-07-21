<?php

namespace App\Console\Commands;

use App\Mail\OverdueReminderMail;
use App\Services\Email\EmailService;
use App\Services\WorkspaceContextManager;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SendOverdueReminders extends Command
{
    protected $signature = 'email:send-overdue-reminders';
    protected $description = 'Send reminder emails for overdue invoices (with dedup)';

    public function handle(EmailService $emailService, WorkspaceContextManager $workspaceContext): int
    {
        $workspaceIds = DB::table('workspaces')
            ->where('status', 'active')
            ->where('is_active', true)
            ->whereIn('subscription_status', ['freemium', 'trial', 'active'])
            ->pluck('id')
            ->unique();

        $sent = 0;
        foreach ($workspaceIds as $workspaceId) {
            $sent += $workspaceContext->runSystemInWorkspace(
                (string) $workspaceId,
                function () use ($emailService, $workspaceId): int {
                    $overdue = DB::table('invoices as i')
                        ->join('contacts as c', 'c.id', '=', 'i.contact_id')
                        ->where('i.workspace_id', $workspaceId)
                        ->where('i.invoice_type', 'sale')
                        ->where('i.payment_status', 'unpaid')
                        ->where('i.due_date', '<', now()->toDateString())
                        ->whereNotNull('c.email')
                        ->select([
                            'i.id', 'i.workspace_id', 'i.invoice_number', 'i.total_amount',
                            'i.due_date', 'c.name as contact_name', 'c.email as contact_email',
                        ])
                        ->limit(100)
                        ->get();

                    $workspaceSent = 0;
                    foreach ($overdue as $invoice) {
                        $daysOverdue = now()->diffInDays($invoice->due_date);
                        $logId = $emailService->send(
                            $invoice->workspace_id,
                            $invoice->contact_email,
                            $invoice->contact_name,
                            new OverdueReminderMail(
                                $invoice->contact_name,
                                $invoice->invoice_number,
                                (float) $invoice->total_amount,
                                $daysOverdue,
                            ),
                            'overdue_reminder',
                            [
                                'event_name' => 'scheduled:overdue_reminder',
                                'related_entity_type' => 'invoice',
                                'related_entity_id' => $invoice->id,
                            ],
                        );

                        if ($logId) {
                            $workspaceSent++;
                        }
                    }

                    return $workspaceSent;
                },
            );
        }

        $this->info("Overdue reminders sent: {$sent}");

        return self::SUCCESS;
    }
}
