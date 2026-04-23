<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Proactive AI insight generator.
 *
 * Analyzes workspace data and generates structured business suggestions.
 * Can be run on-demand or via scheduled job.
 */
class AiInsightService
{
    /**
     * Generate all insights for a workspace.
     */
    public function generateInsights(string $workspaceId): array
    {
        $insights = [];

        $insights = array_merge($insights, $this->checkLowInventory($workspaceId));
        $insights = array_merge($insights, $this->checkOverdueReceivables($workspaceId));
        $insights = array_merge($insights, $this->checkSalesTrend($workspaceId));
        $insights = array_merge($insights, $this->checkTopProducts($workspaceId));
        $insights = array_merge($insights, $this->checkIdleCustomers($workspaceId));

        // Store insights
        foreach ($insights as $insight) {
            DB::table('ai_insights')->insert(array_merge($insight, [
                'id'           => Str::uuid()->toString(),
                'workspace_id' => $workspaceId,
                'status'       => 'new',
                'created_at'   => now(),
                'updated_at'   => now(),
            ]));
        }

        return $insights;
    }

    /**
     * Get insights for a workspace.
     */
    public function getInsights(string $workspaceId, string $status = 'new', int $limit = 20): array
    {
        return DB::table('ai_insights')
            ->where('workspace_id', $workspaceId)
            ->when($status !== 'all', fn ($q) => $q->where('status', $status))
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get()
            ->toArray();
    }

    /**
     * Dismiss an insight.
     */
    public function dismiss(string $insightId, string $workspaceId): bool
    {
        return DB::table('ai_insights')
            ->where('id', $insightId)
            ->where('workspace_id', $workspaceId)
            ->update(['status' => 'dismissed', 'updated_at' => now()]) > 0;
    }

    /**
     * Mark insight as read.
     */
    public function markRead(string $insightId, string $workspaceId): bool
    {
        return DB::table('ai_insights')
            ->where('id', $insightId)
            ->where('workspace_id', $workspaceId)
            ->update(['status' => 'read', 'updated_at' => now()]) > 0;
    }

    // ── Analyzers ─────────────────────────────────

    private function checkLowInventory(string $wsId): array
    {
        $lowStock = DB::table('inventory_levels as se')
            ->join('products as p', 'p.id', '=', 'se.product_id')
            ->where('se.workspace_id', $wsId)
            ->where('p.is_deleted', false)
            ->whereRaw('se.quantity <= COALESCE(p.min_stock_alert, 5)')
            ->select(['p.id', 'p.name', 'se.quantity', 'p.min_stock_alert'])
            ->limit(10)
            ->get();

        if ($lowStock->isEmpty()) {
            return [];
        }

        $items = $lowStock->map(fn ($s) => [
            'product_id'   => $s->id,
            'product_name' => $s->name,
            'current_qty'  => (float) $s->quantity,
            'min_alert'    => (float) ($s->min_stock_alert ?? 5),
        ])->toArray();

        return [[
            'insight_type' => 'low_inventory',
            'severity'     => 'warning',
            'title'        => count($items) . ' product(s) have low stock levels',
            'detail'       => json_encode(['items' => $items]),
        ]];
    }

    private function checkOverdueReceivables(string $wsId): array
    {
        $overdue = DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('invoice_type', 'sale')
            ->where('payment_status', 'unpaid')
            ->where('due_date', '<', now()->toDateString())
            ->select(['id', 'invoice_number', 'total_amount', 'due_date', 'contact_id'])
            ->limit(10)
            ->get();

        if ($overdue->isEmpty()) {
            return [];
        }

        $totalOverdue = $overdue->sum('total_amount');
        $items = $overdue->map(fn ($inv) => [
            'invoice_id'     => $inv->id,
            'invoice_number' => $inv->invoice_number,
            'amount'         => (float) $inv->total_amount,
            'due_date'       => $inv->due_date,
        ])->toArray();

        return [[
            'insight_type' => 'overdue_receivables',
            'severity'     => 'warning',
            'title'        => count($items) . " overdue invoice(s) totaling " . number_format($totalOverdue, 2),
            'detail'       => json_encode(['total' => $totalOverdue, 'invoices' => $items]),
        ]];
    }

    private function checkSalesTrend(string $wsId): array
    {
        $current = (float) DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('invoice_type', 'sale')
            ->where('created_at', '>=', now()->subDays(30)->toDateString())
            ->sum('total_amount');

        $previous = (float) DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('invoice_type', 'sale')
            ->whereBetween('created_at', [now()->subDays(60)->toDateString(), now()->subDays(30)->toDateString()])
            ->sum('total_amount');

        if ($previous <= 0) {
            return [];
        }

        $ratio = $current / $previous;
        if ($ratio < 0.7) {
            return [[
                'insight_type' => 'sales_trend',
                'severity'     => 'warning',
                'title'        => 'Sales dropped ' . round((1 - $ratio) * 100) . '% compared to prior 30 days',
                'detail'       => json_encode(['current_period' => $current, 'prior_period' => $previous, 'change_pct' => round(($ratio - 1) * 100)]),
            ]];
        }

        return [];
    }

    private function checkTopProducts(string $wsId): array
    {
        $top = DB::table('invoice_items as ii')
            ->join('invoices as inv', 'inv.id', '=', 'ii.invoice_id')
            ->join('products as p', 'p.id', '=', 'ii.product_id')
            ->where('inv.workspace_id', $wsId)
            ->where('inv.invoice_type', 'sale')
            ->where('inv.created_at', '>=', now()->subDays(30)->toDateString())
            ->groupBy('p.id', 'p.name')
            ->select([
                'p.id', 'p.name',
                DB::raw('SUM(ii.subtotal) as revenue'),
                DB::raw('SUM(ii.quantity) as qty_sold'),
            ])
            ->orderByDesc('revenue')
            ->limit(5)
            ->get();

        if ($top->isEmpty()) {
            return [];
        }

        return [[
            'insight_type' => 'top_products',
            'severity'     => 'info',
            'title'        => 'Top 5 products by revenue (last 30 days)',
            'detail'       => json_encode(['products' => $top->toArray()]),
        ]];
    }

    private function checkIdleCustomers(string $wsId): array
    {
        $idle = DB::table('contacts as c')
            ->leftJoin('invoices as inv', function ($j) use ($wsId) {
                $j->on('inv.contact_id', '=', 'c.id')
                    ->where('inv.workspace_id', $wsId)
                    ->where('inv.created_at', '>=', now()->subDays(90)->toDateString());
            })
            ->where('c.workspace_id', $wsId)
            ->where('c.type', 'customer')
            ->whereNull('inv.id')
            ->select(['c.id', 'c.name', 'c.email'])
            ->limit(10)
            ->get();

        if ($idle->isEmpty()) {
            return [];
        }

        return [[
            'insight_type' => 'idle_customers',
            'severity'     => 'info',
            'title'        => count($idle->toArray()) . ' customer(s) with no activity in 90 days',
            'detail'       => json_encode(['customers' => $idle->toArray()]),
        ]];
    }
}
