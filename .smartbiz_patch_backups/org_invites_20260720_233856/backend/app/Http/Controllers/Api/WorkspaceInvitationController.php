<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MembershipRole;
use App\Models\Role;
use App\Models\User;
use App\Models\WorkspaceInvitation;
use App\Models\WorkspaceInvitationRole;
use App\Models\WorkspaceMembership;
use App\Services\AuthSessionPayloadBuilder;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * WorkspaceInvitationController — multi-role invite support.
 *
 * Authenticated workspace-scoped:
 *   GET  /api/workspace-invitations
 *   POST /api/workspace-invitations
 *   POST /api/workspace-invitations/{id}/revoke
 *
 * Public:
 *   GET  /api/invites/{token}
 *   POST /api/invites/{token}/accept
 */
class WorkspaceInvitationController extends Controller
{
    private const INVITE_ROLE_KEYS = ['owner', 'admin', 'general_manager'];

    // ═══════════════════════════════════════════════════════════
    //  Authenticated Workspace-Scoped Endpoints
    // ═══════════════════════════════════════════════════════════

    /**
     * GET /api/workspace-invitations
     */
    public function index(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $invites = WorkspaceInvitation::where('workspace_id', $ctx->workspaceId())
            ->with(['role', 'invitedByUser', 'invitationRoles.role'])
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();

        $data = $invites->map(fn ($inv) => $this->invitePayload($inv));

        return response()->json(['data' => $data]);
    }

    /**
     * POST /api/workspace-invitations
     *
     * Create invite with multi-role support.
     * Accepts old format (role_id) or new format (role_ids + primary_role_id).
     */
    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeInviteCreation($ctx);

        $validated = $request->validate([
            'email'           => 'required|email|max:255',
            'full_name'       => 'nullable|string|max:255',
            'role_id'         => 'nullable|uuid',
            'role_ids'        => 'nullable|array|min:1',
            'role_ids.*'      => 'uuid',
            'primary_role_id' => 'nullable|uuid',
            'expires_in_days' => 'nullable|integer|min:1|max:30',
        ]);

        // Normalize: support both old and new format
        $roleIds = $validated['role_ids'] ?? [];
        if (empty($roleIds) && ! empty($validated['role_id'])) {
            $roleIds = [$validated['role_id']];
        }

        if (empty($roleIds)) {
            return response()->json([
                'message' => 'At least one role is required.',
                'errors'  => ['role_ids' => ['Provide role_ids or role_id.']],
            ], 422);
        }

        $primaryRoleId = $validated['primary_role_id'] ?? $roleIds[0];

        if (! in_array($primaryRoleId, $roleIds, true)) {
            return response()->json([
                'message' => 'Primary role must be one of the selected roles.',
                'errors'  => ['primary_role_id' => ['Must be in role_ids.']],
            ], 422);
        }

        // Verify all roles belong to workspace
        $roles = Role::where('workspace_id', $ctx->workspaceId())
            ->whereIn('id', $roleIds)
            ->get();

        if ($roles->count() !== count(array_unique($roleIds))) {
            return response()->json([
                'message' => 'One or more roles do not belong to this workspace.',
                'errors'  => ['role_ids' => ['Invalid role for this workspace.']],
            ], 422);
        }

        // Block owner role in invite
        if ($roles->contains(fn ($r) => $r->role_key === 'owner')) {
            return response()->json([
                'message' => 'Cannot invite someone as owner.',
            ], 403);
        }

        // Check for duplicate pending invite
        $existing = WorkspaceInvitation::where('workspace_id', $ctx->workspaceId())
            ->where('email', $validated['email'])
            ->where('status', 'pending')
            ->where('expires_at', '>', now())
            ->first();

        if ($existing) {
            return response()->json([
                'message' => 'A pending invite already exists for this email.',
                'errors'  => ['email' => ['A pending invite already exists.']],
            ], 409);
        }

        // Generate secure token
        $rawToken = Str::random(64);
        $tokenHash = hash('sha256', $rawToken);
        $expiresInDays = $validated['expires_in_days'] ?? 7;

        $invitation = DB::transaction(function () use ($ctx, $validated, $roleIds, $primaryRoleId, $tokenHash, $expiresInDays) {
            $user = request()->user();

            $invitation = WorkspaceInvitation::create([
                'workspace_id'       => $ctx->workspaceId(),
                'email'              => $validated['email'],
                'full_name'          => $validated['full_name'] ?? null,
                'role_id'            => $primaryRoleId, // Legacy/backward compat
                'invited_by_user_id' => $user->id,
                'token_hash'         => $tokenHash,
                'status'             => 'pending',
                'expires_at'         => now()->addDays($expiresInDays),
            ]);

            // Create pivot rows
            foreach ($roleIds as $roleId) {
                WorkspaceInvitationRole::create([
                    'workspace_invitation_id' => $invitation->id,
                    'role_id'                 => $roleId,
                    'is_primary'              => $roleId === $primaryRoleId,
                ]);
            }

            return $invitation;
        });

        $invitation->load(['invitationRoles.role', 'role']);
        $payload = $this->invitePayload($invitation);
        $payload['token'] = $rawToken;
        $payload['invite_path'] = '/invite/' . $rawToken;

        return response()->json(['data' => $payload], 201);
    }

    /**
     * POST /api/workspace-invitations/{id}/revoke
     */
    public function revoke(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $invitation = WorkspaceInvitation::where('workspace_id', $ctx->workspaceId())->find($id);

        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found.'], 404);
        }

        if ($invitation->isAccepted()) {
            return response()->json(['message' => 'Cannot revoke an already accepted invitation.'], 409);
        }

        if ($invitation->isRevoked()) {
            return response()->json(['message' => 'Invitation is already revoked.'], 409);
        }

        $invitation->update([
            'status'     => 'revoked',
            'revoked_at' => now(),
        ]);

        return response()->json(['message' => 'Invitation revoked.']);
    }

    // ═══════════════════════════════════════════════════════════
    //  Public Endpoints (no auth required)
    // ═══════════════════════════════════════════════════════════

    /**
     * GET /api/invites/{token}
     */
    public function preview(string $token): JsonResponse
    {
        $invitation = $this->findByToken($token);

        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found.'], 404);
        }

        if ($invitation->isRevoked()) {
            return response()->json(['message' => 'This invitation has been revoked.'], 410);
        }

        if ($invitation->isAccepted()) {
            return response()->json(['message' => 'This invitation has already been accepted.'], 409);
        }

        if ($invitation->isExpired()) {
            if ($invitation->isPending()) {
                $invitation->update(['status' => 'expired']);
            }
            return response()->json(['message' => 'This invitation has expired.'], 410);
        }

        $invitation->load(['workspace', 'role', 'invitationRoles.role']);

        $invRoles = $invitation->invitationRoles;
        $hasMultiRoles = $invRoles->isNotEmpty();
        $primaryRole = $invitation->primaryInvitationRole();

        return response()->json([
            'data' => [
                'email'          => $invitation->email,
                'full_name'      => $invitation->full_name,
                'workspace_name' => $invitation->workspace?->name,
                // Legacy single role
                'role_name'      => $primaryRole?->name,
                'role_key'       => $primaryRole?->role_key,
                // Multi-role
                'roles' => $hasMultiRoles
                    ? $invRoles->map(fn ($ir) => [
                        'role_id'    => $ir->role_id,
                        'role_key'   => $ir->role?->role_key,
                        'name'       => $ir->role?->name,
                        'is_primary' => $ir->is_primary,
                    ])->values()->toArray()
                    : ($invitation->role ? [[
                        'role_id'    => $invitation->role->id,
                        'role_key'   => $invitation->role->role_key,
                        'name'       => $invitation->role->name,
                        'is_primary' => true,
                    ]] : []),
                'primary_role' => $primaryRole ? [
                    'role_id'  => $primaryRole->id,
                    'role_key' => $primaryRole->role_key,
                    'name'     => $primaryRole->name,
                ] : null,
                'expires_at' => $invitation->expires_at->toIso8601String(),
            ],
        ]);
    }

    /**
     * POST /api/invites/{token}/accept
     *
     * Accept with multi-role support.
     */
    public function accept(Request $request, string $token): JsonResponse
    {
        $invitation = $this->findByToken($token);

        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found.'], 404);
        }

        if ($invitation->isRevoked()) {
            return response()->json(['message' => 'This invitation has been revoked.'], 410);
        }

        if ($invitation->isAccepted()) {
            return response()->json(['message' => 'This invitation has already been accepted.'], 409);
        }

        if ($invitation->isExpired()) {
            if ($invitation->isPending()) {
                $invitation->update(['status' => 'expired']);
            }
            return response()->json(['message' => 'This invitation has expired.'], 410);
        }

        $validated = $request->validate([
            'full_name'        => 'required|string|max:255',
            'phone_number'     => ['required', 'string', 'min:7', 'max:30', 'regex:/^[0-9+\-\s().]+$/'],
            'password'         => 'required|string|min:8|confirmed',
            'preferred_locale' => 'nullable|string|in:en,ar',
        ]);

        if (User::where('email', $invitation->email)->exists()) {
            return response()->json([
                'message' => 'This email already has an account. Existing-user invite acceptance will be supported later.',
            ], 409);
        }

        $invitation->load('invitationRoles');

        try {
            $result = DB::transaction(function () use ($invitation, $validated) {
                // 1. Create User
                $user = User::create([
                    'full_name'        => $validated['full_name'],
                    'email'            => $invitation->email,
                    'phone_number'     => trim($validated['phone_number']),
                    'password_hash'    => Hash::make($validated['password']),
                    'is_active'        => true,
                    'is_super_admin'   => false,
                    'preferred_locale' => $validated['preferred_locale'] ?? 'ar',
                ]);

                // 2. Create WorkspaceMembership
                $membership = WorkspaceMembership::create([
                    'workspace_id' => $invitation->workspace_id,
                    'user_id'      => $user->id,
                    'status'       => 'active',
                    'joined_at'    => now(),
                ]);

                // 3. Assign roles (multi-role from pivot or legacy fallback)
                $invRoles = $invitation->invitationRoles;

                if ($invRoles->isNotEmpty()) {
                    foreach ($invRoles as $ir) {
                        MembershipRole::create([
                            'workspace_id'  => $invitation->workspace_id,
                            'membership_id' => $membership->id,
                            'role_id'       => $ir->role_id,
                            'is_primary'    => $ir->is_primary,
                            'assigned_at'   => now(),
                        ]);
                    }
                } elseif ($invitation->role_id) {
                    // Legacy single-role fallback
                    MembershipRole::create([
                        'workspace_id'  => $invitation->workspace_id,
                        'membership_id' => $membership->id,
                        'role_id'       => $invitation->role_id,
                        'is_primary'    => true,
                        'assigned_at'   => now(),
                    ]);
                }

                // 4. Update invitation
                $invitation->update([
                    'status'           => 'accepted',
                    'accepted_at'      => now(),
                    'accepted_user_id' => $user->id,
                ]);

                return $user;
            });
        } catch (\Throwable $e) {
            report($e);
            return response()->json([
                'message' => 'Failed to accept invitation. Please try again.',
            ], 500);
        }

        $user = $result->fresh();
        $sanctumToken = $user->createToken(
            name: 'api',
            expiresAt: now()->addHours(24),
        );

        $session = AuthSessionPayloadBuilder::build($user);

        return response()->json(array_merge(
            ['token' => $sanctumToken->plainTextToken],
            $session,
        ), 201);
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function findByToken(string $token): ?WorkspaceInvitation
    {
        $hash = hash('sha256', $token);
        return WorkspaceInvitation::where('token_hash', $hash)->first();
    }

    private function invitePayload(WorkspaceInvitation $inv): array
    {
        $invRoles = $inv->invitationRoles ?? collect();
        $primaryRole = $inv->primaryInvitationRole();

        return [
            'id'          => $inv->id,
            'email'       => $inv->email,
            'full_name'   => $inv->full_name,
            // Legacy single role (backward compat)
            'role'        => $primaryRole ? [
                'id'       => $primaryRole->id,
                'role_key' => $primaryRole->role_key,
                'name'     => $primaryRole->name,
            ] : null,
            // Multi-role
            'roles'       => $invRoles->isNotEmpty()
                ? $invRoles->map(fn ($ir) => [
                    'role_id'    => $ir->role_id,
                    'role_key'   => $ir->role?->role_key,
                    'name'       => $ir->role?->name,
                    'is_primary' => $ir->is_primary,
                ])->values()->toArray()
                : ($inv->role ? [[
                    'role_id'    => $inv->role->id,
                    'role_key'   => $inv->role->role_key,
                    'name'       => $inv->role->name,
                    'is_primary' => true,
                ]] : []),
            'primary_role' => $primaryRole ? [
                'role_id'  => $primaryRole->id,
                'role_key' => $primaryRole->role_key,
                'name'     => $primaryRole->name,
            ] : null,
            'status'      => $inv->isExpired() && $inv->isPending() ? 'expired' : $inv->status,
            'invited_by'  => $inv->invitedByUser ? [
                'id'        => $inv->invitedByUser->id,
                'full_name' => $inv->invitedByUser->full_name,
            ] : null,
            'expires_at'  => $inv->expires_at->toIso8601String(),
            'accepted_at' => $inv->accepted_at?->toIso8601String(),
            'created_at'  => $inv->created_at->toIso8601String(),
        ];
    }

    private function authorizeInviteCreation(WorkspaceContextManager $ctx): void
    {
        $membership = WorkspaceMembership::where('id', $ctx->membershipId())->first();

        if (! $membership) {
            abort(403, 'No active membership in this workspace.');
        }

        $roleKeys = $membership->membershipRoles()
            ->with('role')
            ->get()
            ->pluck('role.role_key')
            ->toArray();

        if (empty(array_intersect($roleKeys, self::INVITE_ROLE_KEYS))) {
            abort(403, 'You do not have permission to invite employees.');
        }
    }
}
