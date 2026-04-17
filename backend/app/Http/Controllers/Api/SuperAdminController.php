<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\AiCreditService;
use App\Services\FeatureFlagService;
use App\Services\BillingPaymentService;
use App\Services\ManualPaymentService;
use App\Services\PlanService;
use App\Services\SubscriptionService;
use App\Services\SuperAdminService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SuperAdminController extends Controller
{
    public function __construct(
        private readonly SuperAdminService   $admin,
        private readonly PlanService         $plans,
        private readonly SubscriptionService $subscriptions,
        private readonly AiCreditService     $credits,
        private readonly FeatureFlagService  $features,
        private readonly BillingPaymentService $payments,
        private readonly ManualPaymentService  $manualPayments,
    ) {}

    // ── Dashboard ─────────────────────────────────────────────

    public function dashboard(): JsonResponse
    {
        return response()->json(['data' => $this->admin->dashboardSummary()]);
    }

    // ── Workspaces ────────────────────────────────────────────

    public function listWorkspaces(): JsonResponse
    {
        return response()->json(['data' => $this->admin->listWorkspaces()]);
    }

    public function showWorkspace(string $id): JsonResponse
    {
        $detail = $this->admin->getWorkspaceDetail($id);
        if (! $detail) return response()->json(['message' => 'Workspace not found.'], 404);
        return response()->json(['data' => $detail]);
    }

    public function updateSubscription(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'plan_id'       => ['required', 'uuid'],
            'plan_price_id' => ['required', 'uuid'],
            'billing_cycle' => ['required', 'string'],
            'is_trial'      => ['sometimes', 'boolean'],
        ]);

        $sub = $this->subscriptions->assignPlan(
            $id,
            $request->input('plan_id'),
            $request->input('plan_price_id'),
            $request->input('billing_cycle'),
            $request->boolean('is_trial', false),
        );

        return response()->json(['data' => $sub]);
    }

    public function updateTrial(Request $request, string $id): JsonResponse
    {
        $request->validate(['extra_days' => ['required', 'integer', 'min:1']]);
        $sub = $this->subscriptions->extendTrial($id, $request->input('extra_days'));
        if (! $sub) return response()->json(['message' => 'Subscription not found.'], 404);
        return response()->json(['data' => $sub]);
    }

    public function updateWorkspaceStatus(Request $request, string $id): JsonResponse
    {
        $request->validate(['status' => ['required', 'in:active,suspended,cancelled']]);

        if ($request->input('status') === 'active') {
            $sub = $this->subscriptions->activateSubscription($id);
        } else {
            $sub = $this->subscriptions->suspendSubscription($id, $request->input('status'));
        }

        if (! $sub) return response()->json(['message' => 'Subscription not found.'], 404);
        return response()->json(['data' => $sub]);
    }

    public function updateFeatures(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'features'              => ['required', 'array'],
            'features.*.key'        => ['required', 'string'],
            'features.*.enabled'    => ['required', 'boolean'],
            'features.*.reason'     => ['sometimes', 'string'],
        ]);

        $results = [];
        foreach ($request->input('features') as $f) {
            $results[] = $this->features->setOverride(
                $id, $f['key'], $f['enabled'],
                $f['reason'] ?? null, $request->user()->id,
            );
        }

        return response()->json(['data' => $results]);
    }

    public function adjustCredits(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'type'    => ['required', 'in:bonus,purchase'],
            'credits' => ['required', 'integer', 'min:1'],
            'reason'  => ['sometimes', 'string'],
        ]);

        $type = $request->input('type');
        $credits = $request->input('credits');
        $actorId = $request->user()->id;

        if ($type === 'bonus') {
            $bal = $this->credits->addBonusCredits($id, $credits, $actorId, $request->input('reason'));
        } else {
            $bal = $this->credits->purchaseCredits($id, $credits, $actorId);
        }

        return response()->json(['data' => $bal]);
    }

    // ── Plans ─────────────────────────────────────────────────

    public function listPlans(): JsonResponse
    {
        return response()->json(['data' => $this->plans->listPlans(false)]);
    }

    public function createPlan(Request $request): JsonResponse
    {
        $request->validate([
            'name'           => ['required', 'string', 'max:100'],
            'slug'           => ['required', 'string', 'max:100', 'unique:platform_plans,slug'],
            'description'    => ['sometimes', 'string'],
            'max_employees'  => ['required', 'integer', 'min:1'],
            'max_workspaces' => ['sometimes', 'integer', 'min:1'],
        ]);

        $plan = $this->plans->createPlan($request->only([
            'name', 'slug', 'description', 'max_employees', 'max_workspaces', 'sort_order',
        ]));

        return response()->json(['data' => $plan], 201);
    }

    public function updatePlan(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'name'           => ['sometimes', 'string', 'max:100'],
            'description'    => ['sometimes', 'string'],
            'max_employees'  => ['sometimes', 'integer', 'min:1'],
            'max_workspaces' => ['sometimes', 'integer', 'min:1'],
            'is_active'      => ['sometimes', 'boolean'],
        ]);

        $plan = $this->plans->updatePlan($id, $request->only([
            'name', 'description', 'max_employees', 'max_workspaces', 'is_active', 'sort_order',
        ]));
        if (! $plan) return response()->json(['message' => 'Plan not found.'], 404);

        return response()->json(['data' => $plan]);
    }

    public function addPricing(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'billing_cycle'               => ['required', 'in:monthly,quarterly,semi_annual,annual,multi_year,custom'],
            'base_price'                  => ['required', 'numeric', 'min:0'],
            'included_employees'          => ['required', 'integer', 'min:1'],
            'price_per_employee'          => ['required', 'numeric', 'min:0'],
            'included_ai_credits'         => ['required', 'integer', 'min:0'],
            'ai_overage_price_per_credit' => ['required', 'numeric', 'min:0'],
            'currency'                    => ['sometimes', 'string', 'size:3'],
            'effective_from'              => ['sometimes', 'date'],
        ]);

        $pricing = $this->plans->addPricing($id, $request->only([
            'billing_cycle', 'base_price', 'included_employees',
            'price_per_employee', 'included_ai_credits',
            'ai_overage_price_per_credit', 'currency', 'effective_from',
        ]));

        return response()->json(['data' => $pricing], 201);
    }

    // ── Settings ──────────────────────────────────────────────

    public function getSettings(): JsonResponse
    {
        return response()->json(['data' => $this->admin->getSettings()]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $request->validate(['settings' => ['required', 'array']]);
        $this->admin->updateSettings($request->input('settings'), $request->user()->id);
        return response()->json(['data' => $this->admin->getSettings()]);
    }

    // ── Monitoring ────────────────────────────────────────────

    public function highUsage(Request $request): JsonResponse
    {
        $threshold = $request->integer('threshold', 80);
        return response()->json(['data' => $this->admin->highUsageWorkspaces($threshold)]);
    }

    // ── Billing ───────────────────────────────────────────────

    public function setupBilling(string $id): JsonResponse
    {
        $sub = $this->payments->setupBilling($id);
        return response()->json(['data' => $sub]);
    }

    public function paymentHistory(string $id): JsonResponse
    {
        $payments = $this->payments->paymentHistory($id);
        return response()->json(['data' => $payments]);
    }

    // ── Manual Payments ───────────────────────────────────────

    public function submitManualPayment(Request $request): JsonResponse
    {
        $request->validate([
            'amount'        => ['required', 'numeric', 'min:0.01'],
            'method'        => ['required', 'in:manual_cash,bank_transfer,cheque,enterprise_manual'],
            'reference'     => ['sometimes', 'string', 'max:100'],
            'plan_id'       => ['sometimes', 'uuid'],
            'billing_cycle' => ['sometimes', 'string'],
            'notes'         => ['sometimes', 'string'],
            'currency'      => ['sometimes', 'string', 'size:3'],
        ]);

        $ctx = app(\App\Services\WorkspaceContextManager::class);

        $mp = $this->manualPayments->submit(
            $ctx->workspaceId(),
            $request->user()->id,
            $request->only(['amount', 'method', 'reference', 'plan_id', 'billing_cycle', 'notes', 'currency']),
        );

        return response()->json(['data' => $mp], 201);
    }

    public function listManualPayments(): JsonResponse
    {
        return response()->json(['data' => $this->manualPayments->listPending()]);
    }

    public function confirmManualPayment(string $id, Request $request): JsonResponse
    {
        $mp = $this->manualPayments->confirm($id, $request->user()->id);
        return response()->json(['data' => $mp]);
    }

    public function rejectManualPayment(string $id, Request $request): JsonResponse
    {
        $request->validate(['reason' => ['required', 'string']]);
        $mp = $this->manualPayments->reject($id, $request->user()->id, $request->input('reason'));
        return response()->json(['data' => $mp]);
    }
}
