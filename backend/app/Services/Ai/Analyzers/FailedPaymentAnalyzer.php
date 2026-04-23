<?php
namespace App\Services\Ai\Analyzers;

use Illuminate\Support\Facades\DB;

class FailedPaymentAnalyzer implements AnalyzerInterface
{
    public function analyze(string $workspaceId): array
    {
        $failed = DB::table('email_logs')
            ->where('workspace_id', $workspaceId)
            ->where('template', 'payment_failed')
            ->where('created_at', '>=', now()->subDays(7))
            ->count();

        if ($failed === 0) return [];

        return [[
            'category'         => 'operational',
            'title'            => "{$failed} failed payment(s) in the last 7 days",
            'description'      => "There have been {$failed} failed payment notification(s) recently. This may indicate billing issues that require attention.",
            'impact_level'     => $failed >= 3 ? 'high' : 'medium',
            'confidence_score' => 85,
            'reasoning'        => "Counted payment_failed email log entries from the last 7 days as a proxy for payment failures.",
            'data_triggers'    => json_encode(['failed_count' => $failed, 'period' => '7_days']),
            'expected_impact'  => "Resolving payment issues prevents subscription churn and revenue loss.",
            'action_type'      => null,
            'action_payload'   => json_encode([]),
            'related_entities' => json_encode([]),
            'analyzer'         => 'FailedPaymentAnalyzer',
            'dedup_key'        => 'failed_payments:' . now()->toDateString(),
        ]];
    }
}
