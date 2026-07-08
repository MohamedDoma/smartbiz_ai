<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Models\MembershipRole;
use App\Models\PlatformPlan;
use App\Models\Role;
use App\Models\User;
use App\Models\Workspace;
use App\Models\WorkspaceMembership;
use App\Models\WorkspaceSubscription;
use App\Services\AuthSessionPayloadBuilder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    /**
     * POST /api/auth/login
     *
     * Authenticates via email + password_hash, returns a Sanctum API token
     * and the full session payload for frontend routing.
     */
    public function login(LoginRequest $request): JsonResponse
    {
        $validated = $request->validated();

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password_hash)) {
            return response()->json([
                'message' => 'Invalid credentials.',
            ], 401);
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => 'Account is deactivated.',
            ], 403);
        }

        // Create Sanctum token — name identifies the device/session.
        $token = $user->createToken(
            name: 'api',
            expiresAt: now()->addHours(24),
        );

        $session = $this->buildSessionPayload($user);

        return response()->json(array_merge(
            ['token' => $token->plainTextToken],
            $session,
        ));
    }

    /**
     * POST /api/auth/register
     *
     * Registers a new business owner with their workspace.
     * Creates: User, Workspace, Membership, Owner Role, MembershipRole.
     * Optionally creates a trial subscription if a free/starter plan exists.
     *
     * Returns 201 with the same session payload shape as login/me.
     */
    public function register(Request $request): JsonResponse
    {
        // ── Validation ────────────────────────────────────────
        $validated = $request->validate([
            'full_name'             => 'required|string|max:255',
            'email'                 => 'required|email|max:255|unique:users,email',
            'password'              => 'required|string|min:8|confirmed',
            'phone_number'          => ['required', 'string', 'min:7', 'max:30', 'regex:/^[0-9+\-\s().]+$/'],
            'workspace_name'        => 'nullable|string|max:255',
            'business_name'         => 'nullable|string|max:255',
            'business_type'         => 'nullable|string|max:100',
            'business_size'         => 'nullable|string|max:50',
            'preferred_locale'      => 'nullable|string|in:en,ar',
        ]);

        // Normalize workspace name: accept either field.
        $workspaceName = $validated['workspace_name']
            ?? $validated['business_name']
            ?? null;

        if (empty($workspaceName)) {
            return response()->json([
                'message' => 'The workspace name field is required.',
                'errors'  => [
                    'workspace_name' => ['A workspace or business name is required.'],
                ],
            ], 422);
        }

        // ── Transaction ───────────────────────────────────────
        try {
            $result = DB::transaction(function () use ($validated, $workspaceName) {

                // 1. Create User
                $user = User::create([
                    'full_name'        => $validated['full_name'],
                    'email'            => $validated['email'],
                    'phone_number'     => trim($validated['phone_number']),
                    'password_hash'    => Hash::make($validated['password']),
                    'is_active'        => true,
                    'is_super_admin'   => false,
                    'preferred_locale' => $validated['preferred_locale'] ?? 'ar',
                ]);

                // 2. Create Workspace
                $workspace = Workspace::create([
                    'name'                => $workspaceName,
                    'industry_type'       => $validated['business_type'] ?? null,
                    'business_size'       => $validated['business_size'] ?? null,
                    'subscription_status' => 'trial',
                    'status'              => 'active',
                    'is_active'           => true,
                    'default_locale'      => $validated['preferred_locale'] ?? 'ar',
                    'default_currency'    => 'LYD',
                    'timezone'            => 'Africa/Tripoli',
                    'onboarding_data'     => [
                        'business_type' => $validated['business_type'] ?? null,
                        'business_size' => $validated['business_size'] ?? null,
                        'source'        => 'registration',
                    ],
                ]);

                // 3. Seed system Owner role for this workspace
                $ownerRole = $this->seedOwnerRole($workspace);

                // 4. Create Membership
                $membership = WorkspaceMembership::create([
                    'workspace_id' => $workspace->id,
                    'user_id'      => $user->id,
                    'status'       => 'active',
                    'joined_at'    => now(),
                ]);

                // 5. Assign Owner role to membership
                MembershipRole::create([
                    'workspace_id'  => $workspace->id,
                    'membership_id' => $membership->id,
                    'role_id'       => $ownerRole->id,
                    'is_primary'    => true,
                    'assigned_at'   => now(),
                ]);

                // 6. Optional trial subscription
                $this->createTrialSubscription($workspace);

                return $user;
            });
        } catch (\Illuminate\Validation\ValidationException $e) {
            throw $e; // Let Laravel handle 422
        } catch (\Throwable $e) {
            report($e);
            return response()->json([
                'message' => 'Registration failed. Please try again.',
            ], 500);
        }

        // ── Token + Session Response ──────────────────────────
        $user = $result->fresh();

        $token = $user->createToken(
            name: 'api',
            expiresAt: now()->addHours(24),
        );

        $session = $this->buildSessionPayload($user);

        return response()->json(array_merge(
            ['token' => $token->plainTextToken],
            $session,
        ), 201);
    }

    /**
     * POST /api/auth/logout
     *
     * Revokes the current Sanctum token.
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out.',
        ]);
    }

    /**
     * GET /api/auth/me
     *
     * Returns the authenticated user with their workspace memberships
     * and full session payload for frontend routing/RBAC.
     */
    public function me(Request $request): JsonResponse
    {
        return response()->json(
            $this->buildSessionPayload($request->user())
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  Registration Helpers
    // ═══════════════════════════════════════════════════════════

    /**
     * Seed the system Owner role for a new workspace.
     *
     * Copies the full permission set from the existing seed data (ws1)
     * or uses a comprehensive default permission list.
     */
    private function seedOwnerRole(Workspace $workspace): Role
    {
        // Try to copy permissions from an existing seeded Owner role.
        $templateRole = Role::where('role_key', 'owner')
            ->where('is_system', true)
            ->whereNotNull('permissions')
            ->first();

        $permissions = $templateRole?->permissions ?? $this->defaultOwnerPermissions();

        return Role::create([
            'workspace_id'   => $workspace->id,
            'name'           => 'Owner',
            'role_key'       => 'owner',
            'description'    => 'Workspace owner with full access',
            'permissions'    => $permissions,
            'hierarchy_level' => 0,
            'is_system'      => true,
            'is_default'     => false,
            'is_deletable'   => false,
        ]);
    }

    /**
     * Fallback owner permissions if no seeded template exists.
     */
    private function defaultOwnerPermissions(): array
    {
        return [
            'contacts.list', 'contacts.show', 'contacts.create', 'contacts.update', 'contacts.delete',
            'categories.list', 'categories.show', 'categories.create', 'categories.update', 'categories.delete',
            'products.list', 'products.show', 'products.create', 'products.update', 'products.delete',
            'invoices.list', 'invoices.show', 'invoices.create', 'invoices.update',
            'accounts.list', 'accounts.show', 'accounts.create', 'accounts.update', 'accounts.delete',
            'orders.list', 'orders.show', 'orders.create', 'orders.update',
            'journal_entries.list', 'journal_entries.show', 'journal_entries.create', 'journal_entries.update',
            'warehouses.list', 'warehouses.show', 'warehouses.create', 'warehouses.update', 'warehouses.delete',
            'payments.list', 'payments.show', 'payments.create',
            'inventory.list', 'inventory.show', 'inventory.create',
            'reservations.list', 'reservations.show', 'reservations.create', 'reservations.update',
            'bom.list', 'bom.show', 'bom.create', 'bom.update', 'bom.delete',
            'production.list', 'production.show', 'production.create', 'production.update',
            'recurring.list', 'recurring.show', 'recurring.create', 'recurring.update', 'recurring.delete',
            'notifications.list', 'notifications.update',
            'audit.list', 'audit.show',
            'reports.view',
            'discovery.manage',
        ];
    }

    /**
     * Create a trial subscription for a new workspace.
     *
     * Uses the first active plan (prefers "Free" or "Starter").
     * Silently skips if no plans are seeded.
     */
    private function createTrialSubscription(Workspace $workspace): void
    {
        $plan = PlatformPlan::where('is_active', true)
            ->orderByRaw("CASE WHEN slug = 'free' THEN 0 WHEN slug = 'starter' THEN 1 ELSE 2 END")
            ->first();

        if (! $plan) {
            return; // No plans seeded — skip, don't block registration.
        }

        // Get first active price for this plan (required NOT NULL column).
        $planPrice = $plan->activePrices()->first() ?? $plan->prices()->first();

        if (! $planPrice) {
            return; // No pricing configured — skip, don't block registration.
        }

        WorkspaceSubscription::create([
            'workspace_id'           => $workspace->id,
            'plan_id'                => $plan->id,
            'plan_price_id'          => $planPrice->id,
            'status'                 => 'trial',
            'billing_cycle'          => $planPrice->billing_cycle ?? 'monthly',
            'current_period_start'   => now(),
            'current_period_end'     => now()->addDays(14),
            'trial_ends_at'          => now()->addDays(14),
            'included_employees'     => $plan->max_employees ?? 5,
            'current_employee_count' => 1,
            'billable_employee_count' => 0,
            'overage_employee_count' => 0,
            'price_per_extra_employee' => 0,
        ]);
    }

    // ═══════════════════════════════════════════════════════════
    //  Session Payload Builder (delegated)
    // ═══════════════════════════════════════════════════════════

    private function buildSessionPayload(User $user): array
    {
        return AuthSessionPayloadBuilder::build($user);
    }
}
