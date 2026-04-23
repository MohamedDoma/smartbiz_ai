<?php

namespace App\Console\Commands;

use App\Mail\OverdueReminderMail;
use App\Services\Email\EmailService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SendOverdueReminders extends Command
{
    protected $signature = 'email:send-overdue-reminders';
    protected $description = 'Send reminder emails for overdue invoices (with dedup)';

    public function handle(EmailService $emailService): int
    {
        $overdue = DB::table('invoices as i')
            ->join('contacts as c', 'c.id', '=', 'i.contact_id')
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

        $sent = 0;
        foreach ($overdue as $inv) {
            $daysOverdue = now()->diffInDays($inv->due_date);

            $logId = $emailService->send(
                $inv->workspace_id,
                $inv->contact_email,
                $inv->contact_name,
                new OverdueReminderMail(
                    $inv->contact_name,
                    $inv->invoice_number,
                    (float) $inv->total_amount,
                    $daysOverdue,
                ),
                'overdue_reminder',
                [
                    'event_name'          => 'scheduled:overdue_reminder',
                    'related_entity_type' => 'invoice',
                    'related_entity_id'   => $inv->id,
                ],
            );

            if ($logId) $sent++;
        }

        $this->info("Overdue reminders sent: {$sent}");
        return self::SUCCESS;
    }
}
