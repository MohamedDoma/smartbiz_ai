<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class RevenueGrowthAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $current = (float) DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->where('created_at', '>=', now()->subDays(30))
            ->sum('total_amount');

        $previous = (float) DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->whereBetween('created_at', [now()->subDays(60), now()->subDays(30)])
            ->sum('total_amount');

        if ($previous <= 0) return [];

        $changePct = round(($current / $previous - 1) * 100, 1);

        if ($changePct >= -15) return []; // Only flag significant declines

        return [[
            'category'         => 'optimization',
            'title'            => "Revenue declined {$changePct}% over the last 30 days",
            'description'      => "Sales revenue dropped from " . number_format($previous, 2) . " to " . number_format($current, 2) . " compared to the prior 30-day period. This may indicate seasonal effects, pricing issues, or market changes.",
            'impact_level'     => $changePct < -30 ? 'high' : 'medium',
            'confidence_score' => 80,
            'reasoning'        => "Compared total sale invoice amounts between current and prior 30-day periods. A decline exceeding 15% triggers this recommendation.",
            'data_triggers'    => json_encode(['current_revenue' => $current, 'previous_revenue' => $previous, 'change_pct' => $changePct]),
            'expected_impact'  => "Identifying root cause and adjusting strategy could recover lost revenue.",
            'action_type'      => null,
            'action_payload'   => json_encode([]),
            'related_entities' => json_encode([]),
            'analyzer'         => 'RevenueGrowthAnalyzer',
            'dedup_key'        => 'revenue_decline:' . now()->toDateString(),
        ]];
    }
}
