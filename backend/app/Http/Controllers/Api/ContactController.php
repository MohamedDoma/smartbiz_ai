<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreContactRequest;
use App\Http\Requests\UpdateContactRequest;
use App\Http\Resources\ContactResource;
use App\Models\Contact;
use App\Models\WorkspaceMembership;
use App\Services\ContactDuplicateService;
use App\Services\ContactScope;
use App\Services\ContactService;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ContactController extends Controller
{
    public function __construct(
        private readonly ContactService $contacts,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * GET /api/contacts
     *
     * List contacts with optional filtering — scoped by ownership permissions.
     * Query params: type, search, per_page.
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = Contact::where('workspace_id', $wsId)
            ->with(['assignedMembership.user:id,full_name']);

        if ($membership) {
            ContactScope::apply($query, $membership);
        }

        if ($request->filled('type')) {
            $query->where('type', $request->input('type'));
        }

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'ilike', "%{$search}%")
                  ->orWhere('email', 'ilike', "%{$search}%")
                  ->orWhere('phone', 'ilike', "%{$search}%");
            });
        }

        $result = $query->orderBy('name')->paginate($request->input('per_page', 25));

        return ContactResource::collection($result);
    }

    /**
     * GET /api/contacts/{id}
     */
    public function show(string $id): JsonResponse
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = Contact::where('workspace_id', $wsId)
            ->with(['assignedMembership.user:id,full_name']);

        if ($membership) {
            ContactScope::apply($query, $membership);
        }

        $contact = $query->where('id', $id)->first();

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        return response()->json([
            'data' => new ContactResource($contact),
        ]);
    }

    /**
     * POST /api/contacts
     */
    public function store(StoreContactRequest $request): JsonResponse
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $currentMembership = $ctx->membership();
        $resolver = app(PermissionResolver::class);

        $validated = $request->validated();

        // ── Duplicate detection ───────────────────────────────────
        $dupSvc = app(ContactDuplicateService::class);
        $dupResult = $dupSvc->check(
            $wsId,
            $validated['phone'] ?? null,
            $validated['email'] ?? null,
            $currentMembership,
        );

        if ($dupResult['duplicate']) {
            $code = $dupResult['code'];
            if ($code === 'contact_duplicate' && $dupResult['contact']) {
                $c = $dupResult['contact'];
                return response()->json([
                    'message'    => 'This customer is already registered.',
                    'error_code' => 'contact_duplicate',
                    'existing'   => [
                        'id'    => $c->id,
                        'name'  => $c->name,
                        'phone' => $c->phone,
                        'email' => $c->email,
                    ],
                ], 409);
            }

            return response()->json([
                'message'    => 'This customer is already registered and assigned to another employee. Contact your sales manager.',
                'error_code' => 'contact_exists_outside_scope',
            ], 409);
        }

        $canAssign = $currentMembership ? $resolver->can($currentMembership, 'contacts.assign') : false;
        $canOwn = $currentMembership ? $resolver->can($currentMembership, 'contacts.own') : false;

        // Resolve assignee
        if ($canAssign && ! empty($validated['assigned_membership_id'])) {
            // Manager picked an assignee — validate they have contacts.own
            $assignError = $this->validateContactAssignee($validated['assigned_membership_id'], $wsId, $currentMembership);
            if ($assignError) {
                return response()->json(['message' => $assignError], 422);
            }
            $resolvedAssigneeId = $validated['assigned_membership_id'];
        } elseif ($canAssign && empty($validated['assigned_membership_id'])) {
            // Manager didn't pick anyone — auto-assign only if they can own
            if ($canOwn) {
                $resolvedAssigneeId = $currentMembership?->id;
            } else {
                return response()->json(['message' => 'An assignee is required. You do not have contacts.own to self-assign.'], 422);
            }
        } elseif (! $canAssign) {
            // No assign permission — reject if they sent someone else
            if (! empty($validated['assigned_membership_id']) && $validated['assigned_membership_id'] !== $currentMembership?->id) {
                return response()->json(['message' => 'You cannot assign customers to other members.'], 403);
            }
            // Auto-assign to creator only if they can own
            if ($canOwn) {
                $resolvedAssigneeId = $currentMembership?->id;
            } else {
                return response()->json(['message' => 'You are not eligible to own customers.'], 403);
            }
        }

        $contact = Contact::create(array_merge($validated, [
            'workspace_id' => $wsId,
            'assigned_membership_id' => $resolvedAssigneeId ?? null,
        ]));

        $contact->load(['assignedMembership.user:id,full_name']);

        return response()->json([
            'data' => new ContactResource($contact),
        ], 201);
    }

    /**
     * PUT /api/contacts/{id}
     */
    public function update(UpdateContactRequest $request, string $id): JsonResponse
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = Contact::where('workspace_id', $wsId);
        if ($membership) {
            ContactScope::apply($query, $membership);
        }
        $contact = $query->where('id', $id)->first();

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        $validated = $request->validated();

        // Handle reassignment if provided
        if (array_key_exists('assigned_membership_id', $validated)) {
            $resolver = app(PermissionResolver::class);
            $canAssign = $membership ? $resolver->can($membership, 'contacts.assign') : false;

            if (! $canAssign) {
                return response()->json(['message' => 'You do not have permission to reassign customers.'], 403);
            }

            if ($validated['assigned_membership_id'] !== null) {
                $assignError = $this->validateContactAssignee($validated['assigned_membership_id'], $wsId, $membership);
                if ($assignError) {
                    return response()->json(['message' => $assignError], 422);
                }
            }
        }

        $contact->update($validated);
        $contact->load(['assignedMembership.user:id,full_name']);

        return response()->json([
            'data' => new ContactResource($contact->fresh()),
        ]);
    }

    /**
     * DELETE /api/contacts/{id}
     */
    public function destroy(string $id): JsonResponse
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = Contact::where('workspace_id', $wsId);
        if ($membership) {
            ContactScope::apply($query, $membership);
        }
        $contact = $query->where('id', $id)->first();

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        $contact->delete();

        return response()->json(['message' => 'Contact deleted.']);
    }

    /**
     * GET /api/contacts/assignable-members
     *
     * Returns active workspace members who are eligible to own customers.
     * Requires: contacts.own permission.
     * Gated by contacts.assign permission.
     *
     * Scope:
     * - contacts.manage_all: workspace-wide eligible salespeople
     * - contacts.manage_team: same-team eligible salespeople only
     * - otherwise: self only
     */
    public function assignableMembers(): JsonResponse
    {
        $ctx = $this->context;
        $wsId = $ctx->workspaceId();
        $currentMembership = $ctx->membership();

        $query = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('status', 'active');

        // Scope based on caller's visibility
        $resolver = app(PermissionResolver::class);
        if ($currentMembership && ! $resolver->can($currentMembership, 'contacts.manage_all')) {
            if ($resolver->can($currentMembership, 'contacts.manage_team')
                && $currentMembership->team_id !== null) {
                $query->where('team_id', $currentMembership->team_id);
            } else {
                $query->where('id', $currentMembership->id);
            }
        }

        $memberships = $query->with([
            'user:id,full_name',
            'membershipRoles.role:id,role_key,name',
            'department:id,name',
            'team:id,name',
        ])->get();

        $assignable = [];

        foreach ($memberships as $m) {
            if (! $resolver->can($m, 'contacts.own')) {
                continue;
            }

            $roles = $m->membershipRoles;
            $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();

            $assignable[] = [
                'membership_id' => $m->id,
                'full_name'     => $m->user?->full_name,
                'role_name'     => $primaryMr?->role?->name,
                'role_key'      => $primaryMr?->role?->role_key,
                'department'    => $m->department?->name,
                'team'          => $m->team?->name,
            ];
        }

        return response()->json(['data' => $assignable]);
    }

    /**
     * Validate that an assignee is active, in workspace, and has contacts.own.
     * For manage_team, also validates same team.
     */
    private function validateContactAssignee(string $membershipId, string $wsId, ?WorkspaceMembership $callerMembership): ?string
    {
        $member = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('id', $membershipId)
            ->where('status', 'active')
            ->first();

        if (! $member) {
            return 'Assigned member not found or inactive in this workspace.';
        }

        $resolver = app(PermissionResolver::class);
        if (! $resolver->can($member, 'contacts.own')) {
            return 'The selected employee is not eligible to own customers.';
        }

        // Team scope check for manage_team callers
        if ($callerMembership
            && ! $resolver->can($callerMembership, 'contacts.manage_all')
            && $resolver->can($callerMembership, 'contacts.manage_team')
            && $callerMembership->team_id !== null
            && $member->team_id !== $callerMembership->team_id) {
            return 'You can only assign customers to members of your team.';
        }

        return null;
    }
}
