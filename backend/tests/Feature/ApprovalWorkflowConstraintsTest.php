<?php

namespace Tests\Feature;

use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\WorkspaceMembership;
use App\Services\PermissionCatalog;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Feature tests for Approval Workflow Builder security constraints.
 *
 * Validates:
 *  - Permission key eligibility enforcement via API
 *  - Membership ID validation (active, same-workspace, unknown)
 *  - Permission catalog response metadata (labels, usable_as_approver)
 *
 * Uses the smartbiz_test database via SmartBizTestCase.
 */
class ApprovalWorkflowConstraintsTest extends SmartBizTestCase
{
    private array $cleanUpIds = [];

    protected function tearDown(): void
    {
        if (! empty($this->cleanUpIds['approval_workflow_steps'])) {
            DB::table('approval_workflow_steps')
                ->whereIn('id', $this->cleanUpIds['approval_workflow_steps'])
                ->delete();
        }
        if (! empty($this->cleanUpIds['approval_workflows'])) {
            DB::table('approval_workflows')
                ->whereIn('id', $this->cleanUpIds['approval_workflows'])
                ->delete();
        }
        if (! empty($this->cleanUpIds['workspace_memberships'])) {
            // Remove test membership_roles first to avoid FK violations
            DB::table('membership_roles')
                ->whereIn('membership_id', $this->cleanUpIds['workspace_memberships'])
                ->delete();
            DB::table('workspace_memberships')
                ->whereIn('id', $this->cleanUpIds['workspace_memberships'])
                ->delete();
        }

        parent::tearDown();
    }

    // ═══════════════════════════════════════════════════════════
    //  A. Permission Key Eligibility — accepted keys
    // ═══════════════════════════════════════════════════════════

    /**
     * approvals.decide IS eligible as approver_permission_key.
     */
    public function test_approvals_decide_is_accepted_as_approver_key(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                    => 'Decide Step',
            'approver_type'           => 'permission',
            'approver_permission_key' => 'approvals.decide',
        ]);

        $r->assertStatus(201);
        $this->assertEquals('approvals.decide', $r->json('data.approver_permission_key'));
        $this->cleanUpIds['approval_workflow_steps'][] = $r->json('data.id');
    }

    /**
     * commissions.approve IS eligible as approver_permission_key.
     */
    public function test_commissions_approve_is_accepted_as_approver_key(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                    => 'Commission Approval Step',
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
        ]);

        $r->assertStatus(201);
        $this->assertEquals('commissions.approve', $r->json('data.approver_permission_key'));
        $this->cleanUpIds['approval_workflow_steps'][] = $r->json('data.id');
    }

    // ═══════════════════════════════════════════════════════════
    //  B. Permission Key Eligibility — rejected keys
    // ═══════════════════════════════════════════════════════════

    /**
     * approvals.manage is NOT eligible — it is an admin permission,
     * not an approver-decision permission.
     */
    public function test_approvals_manage_is_rejected_as_approver_key(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                    => 'Manage Step',
            'approver_type'           => 'permission',
            'approver_permission_key' => 'approvals.manage',
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not eligible', $r->json('message'));
    }

    /**
     * contacts.list is NOT eligible — it is a read-only permission.
     */
    public function test_contacts_list_is_rejected_as_approver_key(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                    => 'Contact List Step',
            'approver_type'           => 'permission',
            'approver_permission_key' => 'contacts.list',
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not eligible', $r->json('message'));
    }

    /**
     * An entirely unknown permission key is rejected.
     */
    public function test_unknown_permission_key_is_rejected(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                    => 'Unknown Perm Step',
            'approver_type'           => 'permission',
            'approver_permission_key' => 'does_not_exist.ever',
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not eligible', $r->json('message'));
    }

    // ═══════════════════════════════════════════════════════════
    //  C. Membership constraints
    // ═══════════════════════════════════════════════════════════

    /**
     * An active membership in the SAME workspace is accepted.
     */
    public function test_active_same_workspace_membership_is_accepted(): void
    {
        $workflow = $this->createTestWorkflow();

        // Use the seeded admin membership which is guaranteed active + same workspace
        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                   => 'Specific Member Step',
            'approver_type'          => 'specific_membership',
            'approver_membership_id' => FoundationSeeder::MEMBERSHIP_ID,
        ]);

        $r->assertStatus(201);
        $this->assertEquals(FoundationSeeder::MEMBERSHIP_ID, $r->json('data.approver_membership_id'));
        $this->cleanUpIds['approval_workflow_steps'][] = $r->json('data.id');
    }

    /**
     * An INACTIVE membership in the same workspace is rejected.
     */
    public function test_inactive_membership_is_rejected(): void
    {
        // Create a suspended membership in the same workspace
        $inactiveMembershipId = (string) Str::uuid();
        $inactiveUserId = (string) Str::uuid();

        // Insert a test user
        DB::table('users')->insertOrIgnore([
            'id'            => $inactiveUserId,
            'full_name'     => 'Inactive Test User',
            'email'         => 'inactive_test_' . substr($inactiveMembershipId, 0, 8) . '@smartbiz.test',
            'phone_number'  => '0000000001',
            'password_hash' => bcrypt('test123'),
            'created_at'    => now(),
            'updated_at'    => now(),
        ]);

        DB::table('workspace_memberships')->insertOrIgnore([
            'id'           => $inactiveMembershipId,
            'workspace_id' => $this->workspaceId,
            'user_id'      => $inactiveUserId,
            'status'       => 'suspended',  // Not active
            'joined_at'    => now(),
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);
        $this->cleanUpIds['workspace_memberships'][] = $inactiveMembershipId;

        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                   => 'Inactive Member Step',
            'approver_type'          => 'specific_membership',
            'approver_membership_id' => $inactiveMembershipId,
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not active', $r->json('message'));

        // Cleanup: remove the test user
        DB::table('users')->where('id', $inactiveUserId)->delete();
    }

    /**
     * A membership from a DIFFERENT workspace is rejected.
     */
    public function test_cross_workspace_membership_is_rejected(): void
    {
        // Create a different workspace + membership
        $otherWorkspaceId = (string) Str::uuid();
        $otherMembershipId = (string) Str::uuid();
        $otherUserId = (string) Str::uuid();

        DB::table('users')->insertOrIgnore([
            'id'            => $otherUserId,
            'full_name'     => 'Other WS User',
            'email'         => 'other_ws_' . substr($otherMembershipId, 0, 8) . '@smartbiz.test',
            'phone_number'  => '0000000002',
            'password_hash' => bcrypt('test123'),
            'created_at'    => now(),
            'updated_at'    => now(),
        ]);

        DB::table('workspaces')->insertOrIgnore([
            'id'           => $otherWorkspaceId,
            'name'         => 'Other Test Workspace',
            'is_active'    => true,
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        DB::table('workspace_memberships')->insertOrIgnore([
            'id'           => $otherMembershipId,
            'workspace_id' => $otherWorkspaceId,  // Different workspace!
            'user_id'      => $otherUserId,
            'status'       => 'active',
            'joined_at'    => now(),
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        $workflow = $this->createTestWorkflow();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                   => 'Cross-WS Member Step',
            'approver_type'          => 'specific_membership',
            'approver_membership_id' => $otherMembershipId,
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not active', $r->json('message'));

        // Cleanup
        DB::table('workspace_memberships')->where('id', $otherMembershipId)->delete();
        DB::table('workspaces')->where('id', $otherWorkspaceId)->delete();
        DB::table('users')->where('id', $otherUserId)->delete();
    }

    /**
     * A completely unknown (non-existent) membership ID is rejected.
     */
    public function test_unknown_membership_id_is_rejected(): void
    {
        $workflow = $this->createTestWorkflow();
        $fakeMembershipId = (string) Str::uuid();

        $r = $this->wsPost("/api/approval-workflows/{$workflow->id}/steps", [
            'name'                   => 'Ghost Member Step',
            'approver_type'          => 'specific_membership',
            'approver_membership_id' => $fakeMembershipId,
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not active', $r->json('message'));
    }

    // ═══════════════════════════════════════════════════════════
    //  D. Permission Catalog API — metadata verification
    // ═══════════════════════════════════════════════════════════

    /**
     * The catalog response includes localized labels and usable_as_approver flags.
     */
    public function test_permission_catalog_includes_metadata(): void
    {
        $r = $this->wsGet('/api/permission-catalog');
        $r->assertOk();

        $data = $r->json('data');
        $this->assertIsArray($data);
        $this->assertNotEmpty($data);

        // Find the approvals category
        $approvalsCategory = collect($data)->firstWhere('category', 'approvals');
        $this->assertNotNull($approvalsCategory, 'Approvals category must exist in catalog.');

        // approvals.decide must have usable_as_approver = true and a label
        $decidePermission = collect($approvalsCategory['permissions'])
            ->firstWhere('key', 'approvals.decide');
        $this->assertNotNull($decidePermission, 'approvals.decide must be in catalog.');
        $this->assertArrayHasKey('label', $decidePermission);
        $this->assertNotEmpty($decidePermission['label'], 'Label must not be empty.');
        $this->assertTrue(
            $decidePermission['usable_as_approver'] ?? false,
            'approvals.decide must be flagged as usable_as_approver.'
        );

        // approvals.manage must NOT have usable_as_approver
        $managePermission = collect($approvalsCategory['permissions'])
            ->firstWhere('key', 'approvals.manage');
        $this->assertNotNull($managePermission, 'approvals.manage must be in catalog.');
        $this->assertFalse(
            $managePermission['usable_as_approver'] ?? false,
            'approvals.manage must NOT be flagged as usable_as_approver.'
        );

        // commissions.approve must also be flagged
        $commissionsCategory = collect($data)->firstWhere('category', 'commissions');
        $this->assertNotNull($commissionsCategory);
        $commApprove = collect($commissionsCategory['permissions'])
            ->firstWhere('key', 'commissions.approve');
        $this->assertNotNull($commApprove, 'commissions.approve must be in catalog.');
        $this->assertTrue(
            $commApprove['usable_as_approver'] ?? false,
            'commissions.approve must be flagged as usable_as_approver.'
        );
    }

    /**
     * Verify that the service-level approverKeys() exactly matches
     * the catalog items with usable_as_approver = true.
     */
    public function test_approver_keys_matches_catalog_flags(): void
    {
        $catalog = PermissionCatalog::all();
        $expectedKeys = [];
        foreach ($catalog as $cat) {
            foreach ($cat['permissions'] as $perm) {
                if (! empty($perm['usable_as_approver'])) {
                    $expectedKeys[] = $perm['key'];
                }
            }
        }

        $approverKeys = PermissionCatalog::approverKeys();

        sort($expectedKeys);
        sort($approverKeys);

        $this->assertEquals($expectedKeys, $approverKeys,
            'approverKeys() must exactly match all catalog entries with usable_as_approver=true.');
    }

    // ═══════════════════════════════════════════════════════════
    //  E. Inline steps validation on workflow creation
    // ═══════════════════════════════════════════════════════════

    /**
     * When creating a workflow with inline steps, invalid approver keys
     * are rejected at the nested level.
     */
    public function test_workflow_create_rejects_inline_step_with_invalid_key(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_inline_reject_' . uniqid(),
            'name'         => 'Inline Rejection Test',
            'entity_type'  => 'commission_entry',
            'steps'        => [
                [
                    'name'                    => 'Valid Step',
                    'approver_type'           => 'permission',
                    'approver_permission_key' => 'approvals.decide',
                ],
                [
                    'name'                    => 'Invalid Step',
                    'approver_type'           => 'permission',
                    'approver_permission_key' => 'contacts.list', // NOT eligible
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('not eligible', $r->json('message'));
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function createTestWorkflow(): ApprovalWorkflow
    {
        $workflow = ApprovalWorkflow::create([
            'workspace_id'       => $this->workspaceId,
            'workflow_key'       => 'test_constraints_' . uniqid(),
            'name'               => 'Test Constraints Workflow',
            'entity_type'        => 'commission_entry',
            'trigger_conditions' => [],
            'is_active'          => true,
            'sort_order'         => 1,
            'created_by'         => FoundationSeeder::MEMBERSHIP_ID,
        ]);
        $this->cleanUpIds['approval_workflows'][] = $workflow->id;

        return $workflow;
    }
}
