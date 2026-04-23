<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class PricingAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $zeroPriced = DB::table('products')
            ->where('workspace_id', $workspaceId)
            ->where('is_deleted', false)
            ->where(function ($q) {
                $q->where('base_price', 0)->orWhereNull('base_price');
            })
            ->select(['id', 'name', 'base_price'])
            ->limit(10)
            ->get();

        if ($zeroPriced->isEmpty()) return [];

        return [[
            'category'         => 'optimization',
            'title'            => $zeroPriced->count() . " product(s) have zero or missing price",
            'description'      => "Products without pricing cannot generate revenue from normal sales. Review and set appropriate base prices.",
            'impact_level'     => 'medium',
            'confidence_score' => 95,
            'reasoning'        => "Scanned products where base_price is 0 or NULL. These items will generate $0 revenue on invoices.",
            'data_triggers'    => json_encode(['zero_priced_products' => $zeroPriced->pluck('name')->toArray()]),
            'expected_impact'  => "Setting correct prices enables revenue capture on future sales.",
            'action_type'      => null,
            'action_payload'   => json_encode([]),
            'related_entities' => json_encode($zeroPriced->map(fn ($p) => ['type' => 'product', 'id' => $p->id])->toArray()),
            'analyzer'         => 'PricingAnalyzer',
            'dedup_key'        => 'pricing_issues:' . now()->toDateString(),
        ]];
    }
}
