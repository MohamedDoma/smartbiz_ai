<?php

namespace App\Services\Ai;

use App\Models\AiToolCall;
use App\Models\WorkspaceMembership;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Step 59.2 — AI Tool Registry.
 *
 * Defines available read-only AI tools, checks permissions via guard,
 * executes tools safely, and logs every invocation to ai_tool_calls.
 *
 * Security rules:
 * - Tool list is hardcoded (no dynamic/arbitrary names).
 * - Every tool has a required_permission checked at execution time.
 * - AI never bypasses permissions.
 * - All results are compact summaries (< 2 KB target).
 * - No write operations in this step.
 */
class AiToolRegistry
{
    public function __construct(
        private readonly AiToolPermissionGuard $guard,
    ) {}

    // ─── Tool Definitions ───────────────────────────────────────

    /**
     * All available tools with their metadata.
     */
    public function allTools(): array
    {
        return [
            [
                'name'        => 'get_current_user_context',
                'description' => 'Get current user info, workspace, role, and permissions summary.',
                'permission'  => null, // authenticated only
                'read_only'   => true,
            ],
            [
                'name'        => 'get_allowed_ai_tools',
                'description' => 'Get list of AI tools currently allowed for this user.',
                'permission'  => null,
                'read_only'   => true,
            ],
            [
                'name'        => 'get_workspace_basic_summary',
                'description' => 'Get basic workspace info: name, member count, departments, teams.',
                'permission'  => null, // any workspace member
                'read_only'   => true,
            ],
            [
                'name'        => 'get_finance_summary',
                'description' => 'Get finance summary: income, expenses, profit/loss, receivables, payables.',
                'permission'  => 'reports.view',
                'read_only'   => true,
            ],
            [
                'name'        => 'get_inventory_summary',
                'description' => 'Get inventory summary: product count, low stock, warehouse count, stock value.',
                'permission'  => 'inventory.list',
                'read_only'   => true,
            ],
            [
                'name'        => 'get_pipeline_summary',
                'description' => 'Get pipeline/sales summary: pipeline count, open deals, won/lost counts, total value.',
                'permission'  => 'pipelines.list',
                'read_only'   => true,
            ],
        ];
    }

    /**
     * Get only tools the current user is allowed to use.
     */
    public function allowedTools(?WorkspaceMembership $membership): array
    {
        return array_values(array_filter($this->allTools(), function ($tool) use ($membership) {
            $check = $this->guard->check($membership, $tool['permission']);
            return $check['allowed'];
        }));
    }

    /**
     * Get names of allowed tools.
     */
    public function allowedToolNames(?WorkspaceMembership $membership): array
    {
        return array_map(fn($t) => $t['name'], $this->allowedTools($membership));
    }

    // ─── Tool Execution ─────────────────────────────────────────

    /**
     * Execute a tool by name with permission check and logging.
     *
     * @return array{success: bool, data?: array, denied?: bool, reason?: string, error?: string}
     */
    public function execute(
        string  $toolName,
        string  $workspaceId,
        ?string $userId,
        ?string $conversationId,
        ?string $messageId,
        ?WorkspaceMembership $membership,
    ): array {
        $start = hrtime(true);

        // Validate tool exists
        $toolDef = $this->findTool($toolName);
        if (!$toolDef) {
            return $this->logAndReturn($workspaceId, $userId, $conversationId, $messageId, $toolName, [
                'success' => false,
                'error'   => "Unknown tool: {$toolName}",
            ], 'failed', null, 0, "Unknown tool: {$toolName}");
        }

        // Step 59.2.1 defense-in-depth: validate membership context
        $ctxCheck = $this->validateMembershipContext($membership, $workspaceId, $userId);
        if ($ctxCheck !== null) {
            $durationMs = (int) ((hrtime(true) - $start) / 1_000_000);
            return $this->logAndReturn(
                $workspaceId, $userId, $conversationId, $messageId, $toolName,
                ['success' => false, 'denied' => true, 'reason' => $ctxCheck],
                'denied', $toolDef['permission'], $durationMs, null, 'context_mismatch',
            );
        }

        // Permission check
        $check = $this->guard->check($membership, $toolDef['permission']);
        if (!$check['allowed']) {
            $durationMs = (int) ((hrtime(true) - $start) / 1_000_000);
            return $this->logAndReturn(
                $workspaceId, $userId, $conversationId, $messageId, $toolName,
                ['success' => false, 'denied' => true, 'reason' => $check['reason']],
                'denied', $toolDef['permission'], $durationMs, null, $check['reason'],
            );
        }

        // Execute
        try {
            $data = $this->executeToolInternal($toolName, $workspaceId, $userId, $membership);
            $durationMs = (int) ((hrtime(true) - $start) / 1_000_000);
            return $this->logAndReturn(
                $workspaceId, $userId, $conversationId, $messageId, $toolName,
                ['success' => true, 'data' => $data],
                'success', $toolDef['permission'], $durationMs, null, null, $data,
            );
        } catch (\Throwable $e) {
            $durationMs = (int) ((hrtime(true) - $start) / 1_000_000);
            Log::error('AI tool execution failed', ['tool' => $toolName, 'error' => $e->getMessage()]);
            return $this->logAndReturn(
                $workspaceId, $userId, $conversationId, $messageId, $toolName,
                ['success' => false, 'error' => 'Tool execution failed.'],
                'failed', $toolDef['permission'], $durationMs, $e->getMessage(),
            );
        }
    }

    // ─── Internal Tool Implementations ──────────────────────────

    private function executeToolInternal(string $name, string $wsId, ?string $userId, ?WorkspaceMembership $membership): array
    {
        return match ($name) {
            'get_current_user_context'    => $this->toolUserContext($wsId, $userId, $membership),
            'get_allowed_ai_tools'        => $this->toolAllowedTools($membership),
            'get_workspace_basic_summary' => $this->toolWorkspaceSummary($wsId),
            'get_finance_summary'         => $this->toolFinanceSummary($wsId),
            'get_inventory_summary'       => $this->toolInventorySummary($wsId),
            'get_pipeline_summary'        => $this->toolPipelineSummary($wsId, $membership),
            default => throw new \RuntimeException("No implementation for tool: {$name}"),
        };
    }

    private function toolUserContext(string $wsId, ?string $userId, ?WorkspaceMembership $membership): array
    {
        $user = $userId ? DB::table('users')->where('id', $userId)->first(['id', 'full_name', 'email']) : null;
        $ws   = DB::table('workspaces')->where('id', $wsId)->first(['id', 'name']);

        $roleNames = [];
        if ($membership) {
            $roleNames = DB::table('membership_roles')
                ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
                ->where('membership_roles.membership_id', $membership->id)
                ->pluck('roles.name')
                ->toArray();
        }

        return [
            'user_id'        => $userId,
            'user_name'      => $user?->full_name ?? 'Unknown',
            'user_email'     => $user?->email ?? '',
            'workspace_id'   => $wsId,
            'workspace_name' => $ws?->name ?? 'Unknown',
            'roles'          => $roleNames,
            'membership_id'  => $membership?->id,
        ];
    }

    private function toolAllowedTools(?WorkspaceMembership $membership): array
    {
        $allowed = $this->allowedTools($membership);
        return [
            'tools' => array_map(fn($t) => [
                'name'        => $t['name'],
                'description' => $t['description'],
                'read_only'   => $t['read_only'],
            ], $allowed),
            'count' => count($allowed),
        ];
    }

    private function toolWorkspaceSummary(string $wsId): array
    {
        $ws = DB::table('workspaces')->where('id', $wsId)->first();

        return [
            'workspace_name' => $ws?->name ?? 'Unknown',
            'member_count'   => DB::table('workspace_memberships')->where('workspace_id', $wsId)->where('status', 'active')->count(),
            'departments'    => DB::table('departments')->where('workspace_id', $wsId)->count(),
            'teams'          => DB::table('teams')->where('workspace_id', $wsId)->count(),
            'created_at'     => $ws?->created_at ?? null,
        ];
    }

    private function toolFinanceSummary(string $wsId): array
    {
        // Invoice totals (uses payment_status column, not status)
        $invoices = DB::table('invoices')->where('workspace_id', $wsId)
            ->selectRaw("
                COUNT(*) as total_count,
                COALESCE(SUM(total_amount), 0) as total_revenue,
                COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN total_amount ELSE 0 END), 0) as paid_amount,
                COALESCE(SUM(CASE WHEN payment_status IN ('unpaid', 'partial') THEN total_amount ELSE 0 END), 0) as outstanding
            ")->first();

        // Payment totals
        $payments = DB::table('payments')->where('workspace_id', $wsId)
            ->selectRaw("
                COUNT(*) as payment_count,
                COALESCE(SUM(CASE WHEN status = 'completed' OR is_reversal = false THEN amount ELSE 0 END), 0) as total_received
            ")->first();

        // Account balances (column is 'balance')
        $accountBalance = DB::table('accounts')->where('workspace_id', $wsId)
            ->selectRaw("COALESCE(SUM(balance), 0) as total_balance")
            ->value('total_balance');

        return [
            'invoices_count'      => (int) ($invoices->total_count ?? 0),
            'total_revenue'       => round((float) ($invoices->total_revenue ?? 0), 2),
            'paid_amount'         => round((float) ($invoices->paid_amount ?? 0), 2),
            'outstanding_amount'  => round((float) ($invoices->outstanding ?? 0), 2),
            'payments_count'      => (int) ($payments->payment_count ?? 0),
            'total_received'      => round((float) ($payments->total_received ?? 0), 2),
            'total_account_balance' => round((float) ($accountBalance ?? 0), 2),
            'currency'            => 'SAR',
        ];
    }

    private function toolInventorySummary(string $wsId): array
    {
        // Products use is_deleted (not is_active)
        $products = DB::table('products')->where('workspace_id', $wsId)
            ->selectRaw("
                COUNT(*) as total,
                COALESCE(SUM(CASE WHEN is_deleted = false THEN 1 ELSE 0 END), 0) as active
            ")->first();

        $warehouses = DB::table('warehouses')->where('workspace_id', $wsId)->count();

        // Low stock alert: products with min_stock_alert set
        $lowStockAlert = 0;
        try {
            $lowStockAlert = DB::table('products')
                ->where('workspace_id', $wsId)
                ->where('is_deleted', false)
                ->whereNotNull('min_stock_alert')
                ->where('min_stock_alert', '>', 0)
                ->count();
        } catch (\Throwable $e) {
            // Ignore if column doesn't exist
        }

        return [
            'products_total'         => (int) ($products->total ?? 0),
            'products_active'        => (int) ($products->active ?? 0),
            'warehouses_count'       => $warehouses,
            'products_with_low_stock_alert' => $lowStockAlert,
        ];
    }

    private function toolPipelineSummary(string $wsId, ?WorkspaceMembership $membership): array
    {
        $pipelines = DB::table('pipelines')->where('workspace_id', $wsId)->count();

        // pipeline_records uses value_amount (not value)
        $query = DB::table('pipeline_records')->where('workspace_id', $wsId);
        if ($membership) {
            \App\Services\PipelineRecordScope::applyRaw($query, $membership);
        }
        $records = $query
            ->selectRaw("
                COUNT(*) as total,
                COALESCE(SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END), 0) as open_count,
                COALESCE(SUM(CASE WHEN status = 'won' THEN 1 ELSE 0 END), 0) as won_count,
                COALESCE(SUM(CASE WHEN status = 'lost' THEN 1 ELSE 0 END), 0) as lost_count,
                COALESCE(SUM(CASE WHEN status = 'won' THEN value_amount ELSE 0 END), 0) as won_value,
                COALESCE(SUM(CASE WHEN status = 'open' THEN value_amount ELSE 0 END), 0) as pipeline_value
            ")->first();

        return [
            'pipelines_count' => $pipelines,
            'total_records'   => (int) ($records->total ?? 0),
            'open_count'      => (int) ($records->open_count ?? 0),
            'won_count'       => (int) ($records->won_count ?? 0),
            'lost_count'      => (int) ($records->lost_count ?? 0),
            'won_value'       => round((float) ($records->won_value ?? 0), 2),
            'pipeline_value'  => round((float) ($records->pipeline_value ?? 0), 2),
            'currency'        => 'SAR',
        ];
    }

    // ─── Helpers ────────────────────────────────────────────────

    /**
     * Step 59.2.1 defense-in-depth: validate that the membership matches
     * the request context before executing any tool query.
     *
     * Returns null if valid, or a generic denial reason string if invalid.
     * No sensitive mismatch details are exposed.
     */
    private function validateMembershipContext(
        ?WorkspaceMembership $membership,
        string $workspaceId,
        ?string $userId,
    ): ?string {
        if ($membership === null) {
            return 'لا توجد عضوية فعّالة في مساحة العمل الحالية.';
        }

        if ($membership->status !== 'active') {
            return 'عضويتك في مساحة العمل غير نشطة.';
        }

        if ($membership->workspace_id !== $workspaceId) {
            return 'غير مصرح بالوصول.';
        }

        if ($userId !== null && $membership->user_id !== $userId) {
            return 'غير مصرح بالوصول.';
        }

        return null; // Valid
    }

    private function findTool(string $name): ?array
    {
        foreach ($this->allTools() as $tool) {
            if ($tool['name'] === $name) return $tool;
        }
        return null;
    }

    private function logAndReturn(
        ?string $wsId, ?string $userId, ?string $convoId, ?string $msgId,
        string $toolName, array $result, string $status,
        ?string $permission, int $durationMs,
        ?string $errorMsg = null, ?string $denialReason = null,
        ?array $outputSummary = null,
    ): array {
        try {
            AiToolCall::create([
                'workspace_id'       => $wsId,
                'user_id'            => $userId,
                'conversation_id'    => $convoId,
                'message_id'         => $msgId,
                'tool_name'          => $toolName,
                'status'             => $status,
                'required_permission' => $permission,
                'denial_reason'      => $denialReason,
                'input_payload'      => null,
                'output_summary'     => $outputSummary ? array_slice($outputSummary, 0, 20) : null,
                'duration_ms'        => $durationMs,
                'error_message'      => $errorMsg,
            ]);
        } catch (\Throwable $e) {
            Log::warning('Failed to log AI tool call', ['error' => $e->getMessage()]);
        }

        return $result;
    }
}
