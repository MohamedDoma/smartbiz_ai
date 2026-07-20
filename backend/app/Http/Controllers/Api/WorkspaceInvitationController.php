<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\MembershipRole;
use App\Models\Role;
use App\Models\Team;
use App\Models\User;
use App\Models\WorkspaceInvitation;
use App\Models\WorkspaceInvitationRole;
use App\Models\WorkspaceMembership;
use App\Services\AuthSessionPayloadBuilder;
use App\Services\Invitations\WorkspaceInvitationDeliveryService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class WorkspaceInvitationController extends Controller
{
    public function __construct(
        private readonly WorkspaceInvitationDeliveryService $delivery,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $this->expireStalePending($workspaceId);

        $query = WorkspaceInvitation::where('workspace_id', $workspaceId)
            ->with([
                'workspace:id,name,default_locale',
                'role',
                'department:id,name',
                'team:id,name,department_id',
                'invitedByUser:id,full_name,email',
                'invitationRoles.role',
            ])
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status')->toString());
        }

        if ($request->filled('search')) {
            $search = mb_strtolower(trim($request->string('search')->toString()));
            $query->where(function ($builder) use ($search) {
                $builder->whereRaw('LOWER(email) LIKE ?', ["%{$search}%"])
                    ->orWhereRaw('LOWER(COALESCE(full_name, \'\')) LIKE ?', ["%{$search}%"]);
            });
        }

        return response()->json([
            'data' => $query->limit(200)->get()->map(fn (WorkspaceInvitation $invite) => $this->invitePayload($invite)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $validated = $request->validate([
            'email'           => 'required|email|max:255',
            'full_name'       => 'nullable|string|max:255',
            'role_id'         => 'nullable|uuid',
            'role_ids'        => 'nullable|array|min:1',
            'role_ids.*'      => 'uuid',
            'primary_role_id' => 'nullable|uuid',
            'department_id'   => 'nullable|uuid',
            'team_id'         => 'nullable|uuid',
            'job_title'       => 'nullable|string|max:255',
            'preferred_locale'=> 'nullable|string|in:ar,en',
            'expires_in_days' => 'nullable|integer|min:1|max:30',
        ]);

        $email = mb_strtolower(trim($validated['email']));
        $roleIds = array_values(array_unique($validated['role_ids'] ?? []));
        if ($roleIds === [] && ! empty($validated['role_id'])) {
            $roleIds = [$validated['role_id']];
        }

        if ($roleIds === []) {
            return response()->json([
                'message' => 'At least one role is required.',
                'errors' => ['role_ids' => ['Provide role_ids or role_id.']],
            ], 422);
        }

        $primaryRoleId = $validated['primary_role_id'] ?? $roleIds[0];
        if (! in_array($primaryRoleId, $roleIds, true)) {
            return response()->json([
                'message' => 'Primary role must be one of the selected roles.',
                'errors' => ['primary_role_id' => ['Must be in role_ids.']],
            ], 422);
        }

        $roles = Role::where('workspace_id', $workspaceId)
            ->where('is_active', true)
            ->whereIn('id', $roleIds)
            ->get();

        if ($roles->count() !== count($roleIds)) {
            return response()->json([
                'message' => 'One or more roles do not belong to this workspace.',
                'errors' => ['role_ids' => ['Invalid role for this workspace.']],
            ], 422);
        }

        if ($roles->contains(fn (Role $role) => $role->role_key === 'owner')) {
            return response()->json(['message' => 'The owner role cannot be assigned by invitation.'], 403);
        }

        [$departmentId, $teamId] = $this->resolveAssignment(
            workspaceId: $workspaceId,
            departmentId: $validated['department_id'] ?? null,
            teamId: $validated['team_id'] ?? null,
        );

        $existingUser = User::whereRaw('LOWER(email) = ?', [$email])->first();
        if ($existingUser && WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('user_id', $existingUser->id)
            ->whereIn('status', ['pending', 'active', 'suspended'])
            ->exists()) {
            return response()->json([
                'message' => 'This user already belongs to the workspace.',
                'errors' => ['email' => ['The user is already a workspace member.']],
            ], 409);
        }

        $this->expireStalePending($workspaceId, $email);

        if (WorkspaceInvitation::where('workspace_id', $workspaceId)
            ->whereRaw('LOWER(email) = ?', [$email])
            ->where('status', 'pending')
            ->exists()) {
            return response()->json([
                'message' => 'A pending invite already exists for this email.',
                'errors' => ['email' => ['Use Resend to send the existing invitation again.']],
            ], 409);
        }

        $rawToken = Str::random(64);
        $expiresInDays = $validated['expires_in_days'] ?? 7;
        $locale = $validated['preferred_locale']
            ?? $request->user()?->preferred_locale
            ?? 'ar';

        try {
            $invitation = DB::transaction(function () use (
            $request,
            $workspaceId,
            $email,
            $validated,
            $roleIds,
            $primaryRoleId,
            $departmentId,
            $teamId,
            $locale,
            $rawToken,
            $expiresInDays,
        ) {
            $invitation = WorkspaceInvitation::create([
                'workspace_id'       => $workspaceId,
                'email'              => $email,
                'full_name'          => isset($validated['full_name']) ? trim($validated['full_name']) : null,
                'role_id'            => $primaryRoleId,
                'department_id'      => $departmentId,
                'team_id'            => $teamId,
                'job_title'          => isset($validated['job_title']) ? trim($validated['job_title']) : null,
                'preferred_locale'   => $locale,
                'invited_by_user_id' => $request->user()->id,
                'token_hash'         => hash('sha256', $rawToken),
                'token_encrypted'    => $rawToken,
                'status'             => 'pending',
                'expires_at'         => now()->addDays($expiresInDays),
                'delivery_status'    => 'pending',
            ]);

            foreach ($roleIds as $roleId) {
                WorkspaceInvitationRole::create([
                    'workspace_invitation_id' => $invitation->id,
                    'role_id' => $roleId,
                    'is_primary' => $roleId === $primaryRoleId,
                ]);
            }

            return $invitation;
            });
        } catch (QueryException $e) {
            if ((string) $e->getCode() === '23505') {
                return response()->json([
                    'message' => 'A pending invite already exists for this email.',
                    'errors' => ['email' => ['Use Resend to send the existing invitation again.']],
                ], 409);
            }
            throw $e;
        }

        $sent = $this->delivery->send($invitation, $rawToken);
        $invitation = $this->loadInvitation($invitation->fresh());

        return response()->json([
            'message' => $sent
                ? 'Invitation created and email sent.'
                : 'Invitation created, but the email could not be sent. You can copy the link or resend it.',
            'data' => $this->invitePayload($invitation),
        ], 201);
    }

    public function resend(Request $request, string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $validated = $request->validate([
            'expires_in_days' => 'nullable|integer|min:1|max:30',
        ]);

        $invitation = WorkspaceInvitation::where('workspace_id', $workspaceId)->find($id);
        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found.'], 404);
        }
        if ($invitation->isAccepted()) {
            return response()->json(['message' => 'An accepted invitation cannot be resent.'], 409);
        }

        $otherPending = WorkspaceInvitation::where('workspace_id', $workspaceId)
            ->whereRaw('LOWER(email) = ?', [mb_strtolower($invitation->email)])
            ->where('status', 'pending')
            ->where('id', '!=', $invitation->id)
            ->first();
        if ($otherPending) {
            return response()->json(['message' => 'Another pending invitation already exists for this email.'], 409);
        }

        $rawToken = Str::random(64);
        $invitation->forceFill([
            'token_hash'      => hash('sha256', $rawToken),
            'token_encrypted' => $rawToken,
            'status'          => 'pending',
            'expires_at'      => now()->addDays($validated['expires_in_days'] ?? 7),
            'revoked_at'      => null,
            'delivery_status' => 'pending',
            'delivery_error'  => null,
        ])->save();

        $sent = $this->delivery->send($invitation, $rawToken);
        $invitation = $this->loadInvitation($invitation->fresh());

        return response()->json([
            'message' => $sent
                ? 'Invitation resent successfully.'
                : 'The invitation link was renewed, but email delivery failed.',
            'data' => $this->invitePayload($invitation),
        ]);
    }

    public function revoke(Request $request, string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $invitation = WorkspaceInvitation::where('workspace_id', $workspaceId)->find($id);

        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found.'], 404);
        }
        if ($invitation->isAccepted()) {
            return response()->json(['message' => 'Cannot revoke an accepted invitation.'], 409);
        }
        if ($invitation->isRevoked()) {
            return response()->json(['message' => 'Invitation is already revoked.'], 409);
        }

        $invitation->forceFill([
            'status' => 'revoked',
            'revoked_at' => now(),
        ])->save();

        return response()->json([
            'message' => 'Invitation revoked.',
            'data' => $this->invitePayload($this->loadInvitation($invitation->fresh())),
        ]);
    }

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

        $invitation = $this->loadInvitation($invitation);
        $primaryRole = $invitation->primaryInvitationRole();

        return response()->json(['data' => [
            'email'          => $invitation->email,
            'full_name'      => $invitation->full_name,
            'workspace_name' => $invitation->workspace?->name,
            'role_name'      => $primaryRole?->name,
            'role_key'       => $primaryRole?->role_key,
            'roles'          => $this->rolePayloads($invitation),
            'primary_role'   => $primaryRole ? [
                'role_id' => $primaryRole->id,
                'role_key' => $primaryRole->role_key,
                'name' => $primaryRole->name,
            ] : null,
            'department'     => $invitation->department ? [
                'id' => $invitation->department->id,
                'name' => $invitation->department->name,
            ] : null,
            'team'           => $invitation->team ? [
                'id' => $invitation->team->id,
                'name' => $invitation->team->name,
            ] : null,
            'job_title'      => $invitation->job_title,
            'expires_at'     => $invitation->expires_at->toIso8601String(),
        ]]);
    }

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
            $invitation->update(['status' => 'expired']);
            return response()->json(['message' => 'This invitation has expired.'], 410);
        }

        $validated = $request->validate([
            'full_name'        => 'required|string|max:255',
            'phone_number'     => ['required', 'string', 'min:7', 'max:30', 'regex:/^[0-9+\-\s().]+$/'],
            'password'         => 'required|string|min:8|confirmed',
            'preferred_locale' => 'nullable|string|in:en,ar',
        ]);

        $email = mb_strtolower($invitation->email);
        $existingUser = User::whereRaw('LOWER(email) = ?', [$email])->first();
        if ($existingUser && ! Hash::check($validated['password'], $existingUser->password_hash)) {
            return response()->json([
                'message' => 'This email already has an account. Enter the existing account password to accept the invitation.',
                'errors' => ['password' => ['The password does not match the existing account.']],
            ], 422);
        }
        if ($existingUser && ! $existingUser->is_active) {
            return response()->json(['message' => 'This account is inactive.'], 403);
        }
        if ($existingUser && WorkspaceMembership::where('workspace_id', $invitation->workspace_id)
            ->where('user_id', $existingUser->id)
            ->exists()) {
            return response()->json(['message' => 'This account already belongs to the workspace.'], 409);
        }

        [$departmentId, $teamId] = $this->resolveAssignment(
            workspaceId: $invitation->workspace_id,
            departmentId: $invitation->department_id,
            teamId: $invitation->team_id,
        );

        $roleIds = $invitation->invitationRoles()->pluck('role_id')->all();
        if ($roleIds === [] && $invitation->role_id) {
            $roleIds = [$invitation->role_id];
        }
        $activeRoleCount = Role::where('workspace_id', $invitation->workspace_id)
            ->where('is_active', true)
            ->whereIn('id', $roleIds)
            ->count();
        if ($roleIds === [] || $activeRoleCount !== count(array_unique($roleIds))) {
            return response()->json([
                'message' => 'The roles assigned to this invitation are no longer available. Ask an administrator to resend a new invitation.',
            ], 409);
        }

        try {
            $user = DB::transaction(function () use (
                $invitation,
                $validated,
                $existingUser,
                $departmentId,
                $teamId,
            ) {
                $lockedInvite = WorkspaceInvitation::whereKey($invitation->id)->lockForUpdate()->firstOrFail();
                if (! $lockedInvite->isPending() || $lockedInvite->isExpired()) {
                    throw new \RuntimeException('Invitation is no longer available.');
                }

                $user = $existingUser;
                if (! $user) {
                    $user = User::create([
                        'full_name'        => trim($validated['full_name']),
                        'email'            => mb_strtolower($lockedInvite->email),
                        'phone_number'     => trim($validated['phone_number']),
                        'password_hash'    => Hash::make($validated['password']),
                        'is_active'        => true,
                        'is_super_admin'   => false,
                        'preferred_locale' => $validated['preferred_locale'] ?? $lockedInvite->preferred_locale ?? 'ar',
                    ]);
                }

                $membership = WorkspaceMembership::create([
                    'workspace_id' => $lockedInvite->workspace_id,
                    'user_id'      => $user->id,
                    'department_id'=> $departmentId,
                    'team_id'      => $teamId,
                    'job_title'    => $lockedInvite->job_title,
                    'status'       => 'active',
                    'joined_at'    => now(),
                ]);

                $lockedInvite->load('invitationRoles');
                if ($lockedInvite->invitationRoles->isNotEmpty()) {
                    foreach ($lockedInvite->invitationRoles as $inviteRole) {
                        MembershipRole::create([
                            'workspace_id' => $lockedInvite->workspace_id,
                            'membership_id'=> $membership->id,
                            'role_id'      => $inviteRole->role_id,
                            'is_primary'   => $inviteRole->is_primary,
                            'assigned_at'  => now(),
                        ]);
                    }
                } elseif ($lockedInvite->role_id) {
                    MembershipRole::create([
                        'workspace_id' => $lockedInvite->workspace_id,
                        'membership_id'=> $membership->id,
                        'role_id'      => $lockedInvite->role_id,
                        'is_primary'   => true,
                        'assigned_at'  => now(),
                    ]);
                }

                $lockedInvite->forceFill([
                    'status'           => 'accepted',
                    'accepted_at'      => now(),
                    'accepted_user_id' => $user->id,
                ])->save();

                return $user;
            });
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        } catch (\Throwable $e) {
            report($e);
            return response()->json(['message' => 'Failed to accept invitation. Please try again.'], 500);
        }

        $user = $user->fresh();
        $sanctumToken = $user->createToken(name: 'api', expiresAt: now()->addHours(24));

        return response()->json(array_merge(
            ['token' => $sanctumToken->plainTextToken],
            AuthSessionPayloadBuilder::build($user),
        ), 201);
    }

    private function resolveAssignment(string $workspaceId, ?string $departmentId, ?string $teamId): array
    {
        $department = null;
        if ($departmentId) {
            $department = Department::where('workspace_id', $workspaceId)
                ->where('is_active', true)
                ->find($departmentId);
            abort_unless($department, 422, 'Department does not belong to this workspace or is inactive.');
        }

        if ($teamId) {
            $team = Team::where('workspace_id', $workspaceId)
                ->where('is_active', true)
                ->find($teamId);
            abort_unless($team, 422, 'Team does not belong to this workspace or is inactive.');

            if ($departmentId && $team->department_id && $team->department_id !== $departmentId) {
                abort(422, 'Team does not belong to the specified department.');
            }

            $departmentId ??= $team->department_id;
        }

        return [$departmentId, $teamId];
    }

    private function expireStalePending(string $workspaceId, ?string $email = null): void
    {
        WorkspaceInvitation::where('workspace_id', $workspaceId)
            ->when($email, fn ($query) => $query->whereRaw('LOWER(email) = ?', [mb_strtolower($email)]))
            ->where('status', 'pending')
            ->where('expires_at', '<=', now())
            ->update(['status' => 'expired']);
    }

    private function findByToken(string $token): ?WorkspaceInvitation
    {
        return WorkspaceInvitation::where('token_hash', hash('sha256', $token))->first();
    }

    private function loadInvitation(WorkspaceInvitation $invitation): WorkspaceInvitation
    {
        return $invitation->load([
            'workspace:id,name,default_locale',
            'role',
            'department:id,name',
            'team:id,name,department_id',
            'invitedByUser:id,full_name,email',
            'invitationRoles.role',
        ]);
    }

    private function rolePayloads(WorkspaceInvitation $invitation): array
    {
        if ($invitation->invitationRoles->isNotEmpty()) {
            return $invitation->invitationRoles->map(fn (WorkspaceInvitationRole $inviteRole) => [
                'role_id' => $inviteRole->role_id,
                'role_key' => $inviteRole->role?->role_key,
                'name' => $inviteRole->role?->name,
                'is_primary' => $inviteRole->is_primary,
            ])->values()->toArray();
        }

        return $invitation->role ? [[
            'role_id' => $invitation->role->id,
            'role_key' => $invitation->role->role_key,
            'name' => $invitation->role->name,
            'is_primary' => true,
        ]] : [];
    }

    private function invitePayload(WorkspaceInvitation $invitation): array
    {
        $primaryRole = $invitation->primaryInvitationRole();

        return [
            'id'          => $invitation->id,
            'email'       => $invitation->email,
            'full_name'   => $invitation->full_name,
            'role'        => $primaryRole ? [
                'id' => $primaryRole->id,
                'role_key' => $primaryRole->role_key,
                'name' => $primaryRole->name,
            ] : null,
            'roles'       => $this->rolePayloads($invitation),
            'primary_role'=> $primaryRole ? [
                'role_id' => $primaryRole->id,
                'role_key' => $primaryRole->role_key,
                'name' => $primaryRole->name,
                'is_primary' => true,
            ] : null,
            'department'  => $invitation->department ? [
                'id' => $invitation->department->id,
                'name' => $invitation->department->name,
            ] : null,
            'team'        => $invitation->team ? [
                'id' => $invitation->team->id,
                'name' => $invitation->team->name,
            ] : null,
            'job_title'   => $invitation->job_title,
            'preferred_locale' => $invitation->preferred_locale,
            'status'      => $invitation->isExpired() && $invitation->isPending() ? 'expired' : $invitation->status,
            'invited_by'  => $invitation->invitedByUser ? [
                'id' => $invitation->invitedByUser->id,
                'full_name' => $invitation->invitedByUser->full_name,
            ] : null,
            'invite_url'  => $this->delivery->storedInviteUrl($invitation),
            'invite_path' => $invitation->token_encrypted ? '/invite/' . $invitation->token_encrypted : null,
            'delivery_status' => $invitation->delivery_status,
            'delivery_error'  => $invitation->delivery_error,
            'send_count'      => $invitation->send_count,
            'last_sent_at'    => $invitation->last_sent_at?->toIso8601String(),
            'expires_at'      => $invitation->expires_at?->toIso8601String(),
            'accepted_at'     => $invitation->accepted_at?->toIso8601String(),
            'revoked_at'      => $invitation->revoked_at?->toIso8601String(),
            'created_at'      => $invitation->created_at?->toIso8601String(),
        ];
    }
}
