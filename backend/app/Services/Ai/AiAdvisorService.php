<?php

namespace App\Services\Ai;

use App\Services\Ai\Analyzers\AutomationOpportunityAnalyzer;
use App\Services\Ai\Analyzers\CashFlowRiskAnalyzer;
use App\Services\Ai\Analyzers\CustomerConcentrationAnalyzer;
use App\Services\Ai\Analyzers\FailedPaymentAnalyzer;
use App\Services\Ai\Analyzers\InventoryShortageAnalyzer;
use App\Services\Ai\Analyzers\ModuleSuggestionAnalyzer;
use App\Services\Ai\Analyzers\OverdueInvoiceAnalyzer;
use App\Services\Ai\Analyzers\PricingAnalyzer;
use App\Services\Ai\Analyzers\RevenueGrowthAnalyzer;
use App\Services\Ai\Analyzers\WorkflowGapAnalyzer;
use App\Services\NotificationDispatcher;
use App\Services\ProvisioningService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * AI Advisor — the core differentiator of SmartBiz AI.
 *
 * Runs rule-based analyzers to detect problems, opportunities,
 * and ERP improvement suggestions. Generates scored, explainable
 * recommendations that users can review, accept, reject, or apply.
 */
class AiAdvisorService
{
    private array $analyzers;

    public function __construct(
        private readonly ProvisioningService $provisioning,
        private readonly NotificationDispatcher $notifier,
    ) {
        $this->analyzers = [
            new OverdueInvoiceAnalyzer(),
            new InventoryShortageAnalyzer(),
            new FailedPaymentAnalyzer(),
            new PricingAnalyzer(),
            new RevenueGrowthAnalyzer(),
            new ModuleSuggestionAnalyzer(),
            new WorkflowGapAnalyzer(),
            new CashFlowRiskAnalyzer(),
            new CustomerConcentrationAnalyzer(),
            new AutomationOpportunityAnalyzer(),
        ];
    }

    /**
     * Run all analyzers for a workspace.
     *
     * @return array Generated recommendations
     */
    public function runAnalysis(string $workspaceId): array
    {
        // Set RLS context so analyzer queries pass through row-level security
        DB::statement("SET LOCAL app.workspace_id = '{$workspaceId}'");

        $allRecs = [];

        foreach ($this->analyzers as $analyzer) {
            try {
                $recs = $analyzer->analyze($workspaceId);
                $allRecs = array_merge($allRecs, $recs);
            } catch (\Throwable $e) {
                Log::warning("Analyzer " . get_class($analyzer) . " failed: {$e->getMessage()}", [
                    'workspace_id' => $workspaceId,
                ]);
            }
        }

        // Store recommendations (dedup handled by unique index)
        $stored = [];
        foreach ($allRecs as $rec) {
            try {
                $id = Str::uuid()->toString();
                DB::table('ai_recommendations')->insert(array_merge($rec, [
                    'id'           => $id,
                    'workspace_id' => $workspaceId,
                    'created_at'   => now(),
                    'updated_at'   => now(),
                ]));
                $rec['id'] = $id;
                $stored[] = $rec;

                // Notify on high-impact recommendations
                $this->maybeNotify($workspaceId, $rec);
            } catch (\Illuminate\Database\QueryException $e) {
                // Dedup constraint violation — skip silently
                if (str_contains($e->getMessage(), 'uq_ai_rec_dedup')) {
                    continue;
                }
                throw $e;
            }
        }

        return $stored;
    }

    /**
     * Get recommendations with optional filters.
     */
    public function getRecommendations(
        string  $workspaceId,
        ?string $status = null,
        ?string $category = null,
        int     $limit = 50,
    ): array {
        return DB::table('ai_recommendations')
            ->where('workspace_id', $workspaceId)
            ->when($status, fn ($q) => $q->where('status', $status))
            ->when($category, fn ($q) => $q->where('category', $category))
            ->orderByRaw("CASE impact_level WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")
            ->orderByDesc('confidence_score')
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get()
            ->toArray();
    }

    /**
     * Accept a recommendation.
     */
    public function accept(string $id, string $workspaceId): bool
    {
        return DB::table('ai_recommendations')
            ->where('id', $id)
            ->where('workspace_id', $workspaceId)
            ->where('status', 'pending')
            ->update(['status' => 'accepted', 'updated_at' => now()]) > 0;
    }

    /**
     * Reject a recommendation.
     */
    public function reject(string $id, string $workspaceId, ?string $reason = null): bool
    {
        return DB::table('ai_recommendations')
            ->where('id', $id)
            ->where('workspace_id', $workspaceId)
            ->where('status', 'pending')
            ->update([
                'status'          => 'rejected',
                'rejected_reason' => $reason,
                'updated_at'      => now(),
            ]) > 0;
    }

    /**
     * Dismiss a recommendation (soft ignore).
     */
    public function dismiss(string $id, string $workspaceId): bool
    {
        return DB::table('ai_recommendations')
            ->where('id', $id)
            ->where('workspace_id', $workspaceId)
            ->whereIn('status', ['pending', 'accepted'])
            ->update(['status' => 'dismissed', 'updated_at' => now()]) > 0;
    }

    /**
     * Apply an actionable recommendation.
     *
     * Routes to appropriate service based on action_type.
     */
    public function apply(string $id, string $workspaceId, string $userId): array
    {
        $rec = DB::table('ai_recommendations')
            ->where('id', $id)
            ->where('workspace_id', $workspaceId)
            ->whereIn('status', ['pending', 'accepted'])
            ->first();

        if (! $rec) {
            throw new \InvalidArgumentException('Recommendation not found or not in applicable status.');
        }

        if (! $rec->action_type) {
            throw new \InvalidArgumentException('This recommendation has no actionable operation.');
        }

        $payload = json_decode($rec->action_payload, true) ?? [];

        $result = match ($rec->action_type) {
            'enable_module'        => $this->applyEnableModule($workspaceId, $payload),
            'send_reminders'       => ['applied' => 'reminder_suggestion', 'note' => 'Use email:send-overdue-reminders command or schedule it.'],
            'configure_automation' => ['applied' => 'automation_suggestion', 'payload' => $payload],
            'restock_suggestion'   => ['applied' => 'restock_flagged', 'product_ids' => $payload['product_ids'] ?? []],
            default                => ['applied' => 'noted', 'action_type' => $rec->action_type],
        };

        DB::table('ai_recommendations')->where('id', $id)->update([
            'status'     => 'applied',
            'applied_by' => $userId,
            'applied_at' => now(),
            'updated_at' => now(),
        ]);

        return $result;
    }

    // ── Private Helpers ─────────────────────────────────────

    private function applyEnableModule(string $workspaceId, array $payload): array
    {
        $module = $payload['module'] ?? null;
        if (! $module) {
            return ['error' => 'No module specified'];
        }

        $config = $this->provisioning->getActiveConfig($workspaceId);
        $current = $config?->enabled_modules ?? [];
        if (is_string($current)) $current = json_decode($current, true);

        if (! in_array($module, $current)) {
            $current[] = $module;
            $this->provisioning->updateModules($workspaceId, $current);
        }

        return ['applied' => 'module_enabled', 'module' => $module];
    }

    private function maybeNotify(string $workspaceId, array $rec): void
    {
        if (($rec['impact_level'] ?? '') !== 'high') return;

        // Get workspace owner
        $owner = DB::table('workspace_memberships')
            ->join('users', 'users.id', '=', 'workspace_memberships.user_id')
            ->where('workspace_memberships.workspace_id', $workspaceId)
            ->where('workspace_memberships.status', 'active')
            ->orderBy('workspace_memberships.created_at')
            ->select('users.id', 'users.email', 'users.full_name as name')
            ->first();

        if (! $owner) return;

        $this->notifier->inApp(
            $workspaceId,
            $owner->id,
            '🔔 AI Recommendation: ' . ($rec['title'] ?? 'New recommendation'),
            $rec['description'] ?? '',
            'warning',
        );
    }
}
