<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class CashFlowRiskAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        // Receivables: unpaid sale invoices
        $receivables = (float) DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->where('payment_status', 'unpaid')
            ->sum('total_amount');

        // Payables: unpaid purchase invoices
        $payables = (float) DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'purchase')
            ->where('payment_status', 'unpaid')
            ->sum('total_amount');

        if ($payables <= 0 && $receivables <= 0) return [];

        $ratio = $payables > 0 ? $receivables / $payables : 999;

        // Flag if payables significantly exceed receivables (ratio < 0.8)
        if ($ratio >= 0.8) return [];

        return [[
            'category'         => 'risk',
            'title'            => 'Cash flow risk: payables exceed receivables',
            'description'      => "Outstanding payables (" . number_format($payables, 2) . ") exceed receivables (" . number_format($receivables, 2) . "). This could create short-term cash flow pressure.",
            'impact_level'     => $ratio < 0.5 ? 'high' : 'medium',
            'confidence_score' => 75,
            'reasoning'        => "Compared total unpaid sale invoices (receivables) against unpaid purchase invoices (payables). A ratio below 0.8 indicates potential cash flow strain.",
            'data_triggers'    => json_encode(['receivables' => $receivables, 'payables' => $payables, 'ratio' => round($ratio, 2)]),
            'expected_impact'  => "Accelerating collections or deferring payments can improve cash position.",
            'action_type'      => null,
            'action_payload'   => json_encode([]),
            'related_entities' => json_encode([]),
            'analyzer'         => 'CashFlowRiskAnalyzer',
            'dedup_key'        => 'cashflow_risk:' . now()->toDateString(),
        ]];
    }
}
