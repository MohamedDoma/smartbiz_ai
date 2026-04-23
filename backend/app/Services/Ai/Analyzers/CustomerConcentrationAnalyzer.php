<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class CustomerConcentrationAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $totalRevenue = (float) DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->where('created_at', '>=', now()->subDays(90))
            ->sum('total_amount');

        if ($totalRevenue <= 0) return [];

        $topCustomer = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->where('created_at', '>=', now()->subDays(90))
            ->groupBy('contact_id')
            ->select(['contact_id', DB::raw('SUM(total_amount) as revenue')])
            ->orderByDesc('revenue')
            ->first();

        if (!$topCustomer) return [];

        $concentration = round(($topCustomer->revenue / $totalRevenue) * 100, 1);

        if ($concentration < 40) return []; // Only flag if >40% from one customer

        $contactName = DB::table('contacts')->where('id', $topCustomer->contact_id)->value('name') ?? 'Unknown';

        return [[
            'category'         => 'risk',
            'title'            => "Revenue concentration risk: {$concentration}% from one customer",
            'description'      => "{$contactName} accounts for {$concentration}% of your revenue in the last 90 days. Losing this customer would significantly impact your business. Consider diversifying your customer base.",
            'impact_level'     => $concentration > 60 ? 'high' : 'medium',
            'confidence_score' => 85,
            'reasoning'        => "Calculated each customer's share of total sale revenue over 90 days. Concentration above 40% in a single customer is flagged as a risk.",
            'data_triggers'    => json_encode(['top_customer' => $contactName, 'concentration_pct' => $concentration, 'total_revenue' => $totalRevenue]),
            'expected_impact'  => "Diversifying revenue sources reduces business risk and improves stability.",
            'action_type'      => null,
            'action_payload'   => json_encode([]),
            'related_entities' => json_encode([['type' => 'contact', 'id' => $topCustomer->contact_id]]),
            'analyzer'         => 'CustomerConcentrationAnalyzer',
            'dedup_key'        => 'customer_concentration:' . now()->toDateString(),
        ]];
    }
}
