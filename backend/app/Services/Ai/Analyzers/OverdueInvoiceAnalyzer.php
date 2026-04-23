<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class OverdueInvoiceAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $overdue = DB::table('invoices')
            ->where('workspace_id', $workspaceId)
            ->where('invoice_type', 'sale')
            ->where('payment_status', 'unpaid')
            ->where('due_date', '<', now()->toDateString())
            ->select(['id', 'invoice_number', 'total_amount', 'due_date', 'contact_id'])
            ->limit(20)
            ->get();

        if ($overdue->isEmpty()) return [];

        $totalAmount = $overdue->sum('total_amount');
        $maxDays = $overdue->max(fn ($inv) => now()->diffInDays($inv->due_date));
        $impact = $maxDays > 30 ? 'high' : ($maxDays > 14 ? 'medium' : 'low');
        $confidence = min(95, 60 + $overdue->count() * 3);

        return [[
            'category'         => 'operational',
            'title'            => $overdue->count() . " overdue invoice(s) totaling " . number_format($totalAmount, 2),
            'description'      => "There are {$overdue->count()} unpaid invoices past their due date. The oldest is {$maxDays} days overdue. Total outstanding: " . number_format($totalAmount, 2),
            'impact_level'     => $impact,
            'confidence_score' => $confidence,
            'reasoning'        => "Detected invoices with payment_status='unpaid' and due_date before today. Severity increases with age and total amount.",
            'data_triggers'    => json_encode(['overdue_count' => $overdue->count(), 'total_amount' => $totalAmount, 'max_days_overdue' => $maxDays]),
            'expected_impact'  => "Collecting these invoices would recover " . number_format($totalAmount, 2) . " in revenue.",
            'action_type'      => 'send_reminders',
            'action_payload'   => json_encode(['invoice_ids' => $overdue->pluck('id')->toArray()]),
            'related_entities' => json_encode($overdue->map(fn ($i) => ['type' => 'invoice', 'id' => $i->id])->toArray()),
            'analyzer'         => 'OverdueInvoiceAnalyzer',
            'dedup_key'        => 'overdue_invoices:' . now()->toDateString(),
        ]];
    }
}
