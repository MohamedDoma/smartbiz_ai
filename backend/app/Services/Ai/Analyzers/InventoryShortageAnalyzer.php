<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class InventoryShortageAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $low = DB::table('inventory_levels as il')
            ->join('products as p', 'p.id', '=', 'il.product_id')
            ->where('il.workspace_id', $workspaceId)
            ->where('p.is_deleted', false)
            ->whereRaw('il.quantity <= COALESCE(p.min_stock_alert, 5)')
            ->select(['p.id', 'p.name', 'il.quantity', 'p.min_stock_alert'])
            ->limit(15)
            ->get();

        if ($low->isEmpty()) return [];

        $zeroStock = $low->filter(fn ($p) => $p->quantity <= 0)->count();
        $impact = $zeroStock > 0 ? 'high' : 'medium';

        return [[
            'category'         => 'operational',
            'title'            => $low->count() . " product(s) below minimum stock ({$zeroStock} out of stock)",
            'description'      => "Products are at or below their minimum stock alert levels. {$zeroStock} product(s) are completely out of stock, which may cause lost sales.",
            'impact_level'     => $impact,
            'confidence_score' => 90,
            'reasoning'        => "Compared inventory_levels.quantity against products.min_stock_alert. Out-of-stock items present immediate risk.",
            'data_triggers'    => json_encode(['low_stock_count' => $low->count(), 'zero_stock_count' => $zeroStock, 'products' => $low->pluck('name')->toArray()]),
            'expected_impact'  => "Restocking these items prevents stockouts and potential lost revenue.",
            'action_type'      => 'restock_suggestion',
            'action_payload'   => json_encode(['product_ids' => $low->pluck('id')->toArray()]),
            'related_entities' => json_encode($low->map(fn ($p) => ['type' => 'product', 'id' => $p->id])->toArray()),
            'analyzer'         => 'InventoryShortageAnalyzer',
            'dedup_key'        => 'inventory_shortage:' . now()->toDateString(),
        ]];
    }
}
