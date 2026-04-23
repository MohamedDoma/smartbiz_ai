<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class AutomationOpportunityAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $recommendations = [];

        // Check: high-volume invoicing could benefit from auto-numbering/templates
        $invoiceCount30d = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        if ($invoiceCount30d >= 20) {
            $recommendations[] = [
                'category'         => 'automation',
                'title'            => 'Consider automated invoice generation for recurring customers',
                'description'      => "You created {$invoiceCount30d} invoices in the last 30 days. Recurring invoices for repeat customers could save significant time.",
                'impact_level'     => 'medium',
                'confidence_score' => 70,
                'reasoning'        => "High invoice volume ({$invoiceCount30d} in 30 days) suggests potential for automation through recurring invoice templates.",
                'data_triggers'    => json_encode(['invoice_count_30d' => $invoiceCount30d]),
                'expected_impact'  => "Automating recurring invoices could save hours of manual work monthly.",
                'action_type'      => 'configure_automation',
                'action_payload'   => json_encode(['automation' => 'recurring_invoices']),
                'related_entities' => json_encode([]),
                'analyzer'         => 'AutomationOpportunityAnalyzer',
                'dedup_key'        => 'automation_recurring_invoices:' . now()->toDateString(),
            ];
        }

        // Check: many contacts with no orders — suggest outreach automation
        $idleContacts = DB::table('contacts as c')
            ->leftJoin('invoices as i', function ($j) use ($workspaceId) {
                $j->on('i.contact_id', '=', 'c.id')
                    ->where('i.workspace_id', $workspaceId)
                    ->where('i.created_at', '>=', now()->subDays(60));
            })
            ->where('c.workspace_id', $workspaceId)
            ->where('c.type', 'customer')
            ->whereNull('i.id')
            ->count();

        if ($idleContacts >= 5) {
            $recommendations[] = [
                'category'         => 'automation',
                'title'            => "Set up automated re-engagement for {$idleContacts} idle customers",
                'description'      => "{$idleContacts} customers have had no transactions in 60 days. Automated follow-up emails could re-engage them.",
                'impact_level'     => 'low',
                'confidence_score' => 65,
                'reasoning'        => "Counted customers with no invoice activity in 60 days. Re-engagement automation could recover inactive relationships.",
                'data_triggers'    => json_encode(['idle_customer_count' => $idleContacts]),
                'expected_impact'  => "Re-engaging inactive customers can recover 5-15% of churned revenue.",
                'action_type'      => 'configure_automation',
                'action_payload'   => json_encode(['automation' => 'customer_reengagement']),
                'related_entities' => json_encode([]),
                'analyzer'         => 'AutomationOpportunityAnalyzer',
                'dedup_key'        => 'automation_reengagement:' . now()->toDateString(),
            ];
        }

        return $recommendations;
    }
}
