<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * Workspace-scoped reporting and analytics.
 */
class ReportingService
{
    public function salesSummary(string $workspaceId): array
    {
        $invoices = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->selectRaw("COUNT(*) as total_invoices, COALESCE(SUM(net_amount),0) as total_sales, COALESCE(SUM(CASE WHEN payment_status='paid' THEN net_amount ELSE 0 END),0) as collected")
            ->first();

        $orders = DB::table('orders')
            ->where('workspace_id', $workspaceId)
            ->where('order_type', 'sale_order')
            ->selectRaw("COUNT(*) as total_orders, COALESCE(SUM(total_amount),0) as total_order_value")
            ->first();

        return [
            'total_invoices'    => (int) $invoices->total_invoices,
            'total_sales'       => (float) $invoices->total_sales,
            'collected'         => (float) $invoices->collected,
            'outstanding'       => (float) $invoices->total_sales - (float) $invoices->collected,
            'total_orders'      => (int) $orders->total_orders,
            'total_order_value' => (float) $orders->total_order_value,
        ];
    }

    public function invoicePaymentSummary(string $workspaceId): array
    {
        $result = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->selectRaw("
                payment_status,
                COUNT(*) as count,
                COALESCE(SUM(net_amount),0) as amount
            ")
            ->groupBy('payment_status')
            ->get();

        return $result->map(fn ($r) => [
            'status' => $r->payment_status,
            'count'  => (int) $r->count,
            'amount' => (float) $r->amount,
        ])->toArray();
    }

    public function inventorySummary(string $workspaceId): array
    {
        // Aggregate latest stock per product+warehouse from movements
        $products = DB::select("
            SELECT DISTINCT ON (m.product_id, m.warehouse_id)
                m.product_id,
                m.warehouse_id,
                p.name as product_name,
                p.sku,
                w.name as warehouse_name,
                m.quantity_after as current_stock,
                p.min_stock_alert
            FROM inventory_movements m
            JOIN products p ON p.id = m.product_id
            JOIN warehouses w ON w.id = m.warehouse_id
            WHERE m.workspace_id = ?
            ORDER BY m.product_id, m.warehouse_id, m.created_at DESC, m.id DESC
        ", [$workspaceId]);

        $total = 0;
        $lowStock = [];
        foreach ($products as $p) {
            $total += (float) $p->current_stock;
            if ($p->min_stock_alert !== null && (float) $p->current_stock <= (float) $p->min_stock_alert) {
                $lowStock[] = [
                    'product_name'   => $p->product_name,
                    'sku'            => $p->sku,
                    'warehouse'      => $p->warehouse_name,
                    'current_stock'  => (float) $p->current_stock,
                    'min_alert'      => (float) $p->min_stock_alert,
                ];
            }
        }

        return [
            'total_stock_entries' => count($products),
            'total_units'         => $total,
            'low_stock_count'     => count($lowStock),
            'low_stock_items'     => $lowStock,
        ];
    }

    public function accountBalances(string $workspaceId): array
    {
        $accounts = DB::table('accounts')
            ->where('workspace_id', $workspaceId)
            ->select(['id', 'code', 'name', 'type', 'balance'])
            ->orderBy('code')
            ->get();

        $summary = $accounts->groupBy('type')
            ->map(fn ($group) => [
                'count'   => $group->count(),
                'balance' => $group->sum('balance'),
            ]);

        return [
            'accounts' => $accounts->toArray(),
            'by_type'  => $summary->toArray(),
        ];
    }

    public function receivablePayable(string $workspaceId): array
    {
        $receivable = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->whereIn('payment_status', ['unpaid', 'partial'])
            ->selectRaw("COUNT(*) as count, COALESCE(SUM(net_amount),0) as total")
            ->first();

        $payable = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'purchase')
            ->whereIn('payment_status', ['unpaid', 'partial'])
            ->selectRaw("COUNT(*) as count, COALESCE(SUM(net_amount),0) as total")
            ->first();

        return [
            'receivable' => ['count' => (int) $receivable->count, 'total' => (float) $receivable->total],
            'payable'    => ['count' => (int) $payable->count,    'total' => (float) $payable->total],
        ];
    }
}
