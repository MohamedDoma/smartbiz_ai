<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class WorkflowGapAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $recommendations = [];

        // Check: many invoices but no overdue reminders configured
        $overdueCount = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('payment_status', 'unpaid')
            ->where('due_date', '<', now()->toDateString())
            ->count();

        if ($overdueCount >= 3) {
            $hasReminders = DB::table('email_logs')
                ->where('workspace_id', $workspaceId)
                ->where('template', 'overdue_reminder')
                ->where('created_at', '>=', now()->subDays(30))
                ->exists();

            if (!$hasReminders) {
                $recommendations[] = [
                    'category'         => 'erp',
                    'title'            => 'Set up automated overdue payment reminders',
                    'description'      => "You have {$overdueCount} overdue invoices but no automated reminders have been sent recently. Configure the overdue reminder workflow to automate collections.",
                    'impact_level'     => 'high',
                    'confidence_score' => 90,
                    'reasoning'        => "Detected overdue invoices with no corresponding overdue_reminder emails in the last 30 days.",
                    'data_triggers'    => json_encode(['overdue_count' => $overdueCount]),
                    'expected_impact'  => "Automated reminders improve collection rates by 20-30%.",
                    'action_type'      => 'configure_automation',
                    'action_payload'   => json_encode(['automation' => 'overdue_reminders']),
                    'related_entities' => json_encode([]),
                    'analyzer'         => 'WorkflowGapAnalyzer',
                    'dedup_key'        => 'workflow_overdue_reminders:' . now()->toDateString(),
                ];
            }
        }

        return $recommendations;
    }
}
