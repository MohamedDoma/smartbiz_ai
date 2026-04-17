<?php

namespace App\Services;

use App\Models\ManualPayment;
use App\Models\PaymentTransaction;
use App\Models\WorkspaceSubscription;
use App\Models\PlatformPlanPrice;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Manual / Offline payment service.
 * Supports cash, bank transfer, cheque, enterprise manual payments.
 */
class ManualPaymentService
{
    public function __construct(
        private readonly SubscriptionService $subscriptions,
    ) {}

    /**
     * Submit a manual payment (status=pending).
     */
    public function submit(string $workspaceId, string $userId, array $data): ManualPayment
    {
        return ManualPayment::create([
            'workspace_id'  => $workspaceId,
            'amount'        => $data['amount'],
            'currency'      => $data['currency'] ?? 'usd',
            'method'        => $data['method'],
            'reference'     => $data['reference'] ?? null,
            'plan_id'       => $data['plan_id'] ?? null,
            'billing_cycle' => $data['billing_cycle'] ?? null,
            'notes'         => $data['notes'] ?? null,
            'submitted_by'  => $userId,
            'status'        => 'pending',
            'created_at'    => now(),
        ]);
    }

    /**
     * Confirm a manual payment → activate subscription + record transaction.
     */
    public function confirm(string $paymentId, string $adminId): ManualPayment
    {
        return DB::transaction(function () use ($paymentId, $adminId) {
            $mp = ManualPayment::where('id', $paymentId)
                ->where('status', 'pending')
                ->firstOrFail();

            $mp->update([
                'status'       => 'confirmed',
                'confirmed_by' => $adminId,
                'confirmed_at' => now(),
            ]);

            // Record as payment transaction
            PaymentTransaction::create([
                'workspace_id'             => $mp->workspace_id,
                'stripe_payment_intent_id' => 'manual_' . $mp->id,
                'type'                     => 'subscription',
                'amount'                   => $mp->amount,
                'currency'                 => $mp->currency,
                'status'                   => 'succeeded',
                'description'              => "Manual payment ({$mp->method}): {$mp->reference}",
                'metadata'                 => [
                    'manual_payment_id' => $mp->id,
                    'method'            => $mp->method,
                    'reference'         => $mp->reference,
                ],
                'created_at' => now(),
            ]);

            // Activate subscription if plan specified
            if ($mp->plan_id) {
                $price = PlatformPlanPrice::where('plan_id', $mp->plan_id)
                    ->where('billing_cycle', $mp->billing_cycle ?? 'monthly')
                    ->first();

                if ($price) {
                    $this->subscriptions->assignPlan(
                        $mp->workspace_id,
                        $mp->plan_id,
                        $price->id,
                        $mp->billing_cycle ?? 'monthly',
                        false,
                    );

                    // Set to active
                    WorkspaceSubscription::where('workspace_id', $mp->workspace_id)
                        ->update(['status' => 'active']);
                }
            } else {
                // Just activate existing subscription
                WorkspaceSubscription::where('workspace_id', $mp->workspace_id)
                    ->whereIn('status', ['trial', 'past_due', 'suspended'])
                    ->update(['status' => 'active']);
            }

            Log::info("Manual payment {$paymentId} confirmed by admin {$adminId}");

            return $mp->fresh();
        });
    }

    /**
     * Reject a manual payment.
     */
    public function reject(string $paymentId, string $adminId, string $reason): ManualPayment
    {
        $mp = ManualPayment::where('id', $paymentId)
            ->where('status', 'pending')
            ->firstOrFail();

        $mp->update([
            'status'          => 'rejected',
            'confirmed_by'    => $adminId,
            'rejected_reason' => $reason,
        ]);

        return $mp->fresh();
    }

    /**
     * List pending manual payments (for super-admin).
     */
    public function listPending(): \Illuminate\Database\Eloquent\Collection
    {
        return ManualPayment::where('status', 'pending')
            ->with(['workspace', 'plan', 'submittedBy'])
            ->orderByDesc('created_at')
            ->get();
    }

    /**
     * List manual payments for a workspace.
     */
    public function listForWorkspace(string $workspaceId): \Illuminate\Database\Eloquent\Collection
    {
        return ManualPayment::where('workspace_id', $workspaceId)
            ->orderByDesc('created_at')
            ->get();
    }
}
