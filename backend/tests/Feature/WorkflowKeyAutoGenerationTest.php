<?php

namespace Tests\Feature;

use App\Models\ApprovalWorkflow;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Tests for workflow_key auto-generation and backward compatibility.
 *
 * Verifies:
 *  1.  Create without workflow_key succeeds.
 *  2.  Generated workflow_key is non-empty.
 *  3.  Generated key follows the wf_<ULID> format.
 *  4.  Generated key fits the 100-char column.
 *  5.  Two workflows with the same name receive different keys.
 *  6.  Arabic workflow name creates successfully.
 *  7.  Explicit valid workflow_key is accepted.
 *  8.  Duplicate explicit key is rejected (409).
 *  9.  Editing name does not change workflow_key.
 * 10.  Editing description does not change workflow_key.
 * 11.  Existing workflows remain compatible (list).
 * 12.  Workspace uniqueness — same auto key cannot collide.
 */
class WorkflowKeyAutoGenerationTest extends SmartBizTestCase
{
    private array $cleanUpIds = [];

    protected function tearDown(): void
    {
        if (! empty($this->cleanUpIds)) {
            DB::table('approval_workflow_steps')
                ->whereIn('workflow_id', $this->cleanUpIds)
                ->delete();
            DB::table('approval_workflows')
                ->whereIn('id', $this->cleanUpIds)
                ->delete();
        }

        parent::tearDown();
    }

    private function track(string $id): void
    {
        $this->cleanUpIds[] = $id;
    }

    // ═══════════════════════════════════════════════════════
    //  1. Create without workflow_key succeeds
    // ═══════════════════════════════════════════════════════

    public function test_create_without_workflow_key_succeeds(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Auto Key Test',
            'entity_type' => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));
    }

    // ═══════════════════════════════════════════════════════
    //  2. Generated workflow_key is non-empty
    // ═══════════════════════════════════════════════════════

    public function test_generated_key_is_non_empty(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Non-Empty Key Test',
            'entity_type' => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $key = $r->json('data.workflow_key');
        $this->assertNotNull($key);
        $this->assertNotEmpty($key);
    }

    // ═══════════════════════════════════════════════════════
    //  3. Generated key follows the wf_<ULID> format
    // ═══════════════════════════════════════════════════════

    public function test_generated_key_follows_prefix_format(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Format Test',
            'entity_type' => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $key = $r->json('data.workflow_key');
        $this->assertStringStartsWith('wf_', $key, 'Auto-generated key must start with wf_');
        // ULID is 26 chars, so total = 3 + 26 = 29
        $this->assertEquals(29, strlen($key), 'Auto-generated key must be wf_ + 26-char ULID = 29 chars');
    }

    // ═══════════════════════════════════════════════════════
    //  4. Generated key fits the database column (max 100)
    // ═══════════════════════════════════════════════════════

    public function test_generated_key_fits_column_length(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Column Length Test',
            'entity_type' => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $key = $r->json('data.workflow_key');
        $this->assertLessThanOrEqual(100, strlen($key),
            'Generated key must fit in the 100-char column.');
    }

    // ═══════════════════════════════════════════════════════
    //  5. Same name → different keys
    // ═══════════════════════════════════════════════════════

    public function test_same_name_different_keys(): void
    {
        $r1 = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Duplicate Name Test',
            'entity_type' => 'commission_entry',
        ]);
        $r1->assertStatus(201);
        $this->track($r1->json('data.id'));

        $r2 = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Duplicate Name Test',
            'entity_type' => 'commission_entry',
        ]);
        $r2->assertStatus(201);
        $this->track($r2->json('data.id'));

        $this->assertNotEquals(
            $r1->json('data.workflow_key'),
            $r2->json('data.workflow_key'),
            'Workflows with the same name must receive different auto-generated keys.'
        );
    }

    // ═══════════════════════════════════════════════════════
    //  6. Arabic workflow name creates successfully
    // ═══════════════════════════════════════════════════════

    public function test_arabic_name_creates_successfully(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'اعتماد العمولات المرتفعة',
            'description' => 'يتطلب اعتماد العمولات التي تساوي أو تتجاوز ٥٠٠',
            'entity_type' => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $this->assertEquals('اعتماد العمولات المرتفعة', $r->json('data.name'));
        $this->assertStringStartsWith('wf_', $r->json('data.workflow_key'));
    }

    // ═══════════════════════════════════════════════════════
    //  7. Explicit valid workflow_key is accepted
    // ═══════════════════════════════════════════════════════

    public function test_explicit_key_accepted(): void
    {
        $explicitKey = 'explicit_test_' . uniqid();

        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => $explicitKey,
            'name'         => 'Explicit Key Workflow',
            'entity_type'  => 'commission_entry',
        ]);

        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $this->assertEquals($explicitKey, $r->json('data.workflow_key'),
            'Explicitly provided workflow_key must be used as-is.');
    }

    // ═══════════════════════════════════════════════════════
    //  8. Duplicate explicit key rejected (409)
    // ═══════════════════════════════════════════════════════

    public function test_duplicate_explicit_key_rejected(): void
    {
        $key = 'dup_test_' . uniqid();

        $r1 = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => $key,
            'name'         => 'First',
            'entity_type'  => 'commission_entry',
        ]);
        $r1->assertStatus(201);
        $this->track($r1->json('data.id'));

        $r2 = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => $key,
            'name'         => 'Second',
            'entity_type'  => 'commission_entry',
        ]);
        $r2->assertStatus(409);
    }

    // ═══════════════════════════════════════════════════════
    //  9. Edit name does not change workflow_key
    // ═══════════════════════════════════════════════════════

    public function test_edit_name_preserves_key(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Original Name',
            'entity_type' => 'commission_entry',
        ]);
        $r->assertStatus(201);
        $id = $r->json('data.id');
        $this->track($id);
        $originalKey = $r->json('data.workflow_key');

        $update = $this->wsPut("/api/approval-workflows/{$id}", [
            'name' => 'Updated Name',
        ]);
        $update->assertOk();

        $this->assertEquals($originalKey, $update->json('data.workflow_key'),
            'Editing name must not change workflow_key.');
    }

    // ═══════════════════════════════════════════════════════
    // 10. Edit description does not change workflow_key
    // ═══════════════════════════════════════════════════════

    public function test_edit_description_preserves_key(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Description Test',
            'entity_type' => 'commission_entry',
        ]);
        $r->assertStatus(201);
        $id = $r->json('data.id');
        $this->track($id);
        $originalKey = $r->json('data.workflow_key');

        $update = $this->wsPut("/api/approval-workflows/{$id}", [
            'description' => 'New description added',
        ]);
        $update->assertOk();

        $this->assertEquals($originalKey, $update->json('data.workflow_key'),
            'Editing description must not change workflow_key.');
    }

    // ═══════════════════════════════════════════════════════
    // 11. Existing workflows remain compatible (list)
    // ═══════════════════════════════════════════════════════

    public function test_existing_workflows_list_compatible(): void
    {
        // Create one workflow to guarantee at least one exists
        $r = $this->wsPost('/api/approval-workflows', [
            'name'        => 'Compat Test',
            'entity_type' => 'commission_entry',
        ]);
        $r->assertStatus(201);
        $this->track($r->json('data.id'));

        $list = $this->wsGet('/api/approval-workflows');
        $list->assertOk();

        $data = $list->json('data');
        $this->assertIsArray($data);
        $this->assertNotEmpty($data);

        // Every workflow in the list must have a workflow_key
        foreach ($data as $wf) {
            $this->assertArrayHasKey('workflow_key', $wf);
            $this->assertNotEmpty($wf['workflow_key']);
        }
    }

    // ═══════════════════════════════════════════════════════
    // 12. Workspace uniqueness — auto keys don't collide
    // ═══════════════════════════════════════════════════════

    public function test_auto_keys_are_workspace_unique(): void
    {
        $keys = [];
        for ($i = 0; $i < 5; $i++) {
            $r = $this->wsPost('/api/approval-workflows', [
                'name'        => "Uniqueness Test $i",
                'entity_type' => 'commission_entry',
            ]);
            $r->assertStatus(201);
            $this->track($r->json('data.id'));
            $keys[] = $r->json('data.workflow_key');
        }

        $this->assertCount(5, array_unique($keys),
            'All auto-generated keys must be unique.');
    }
}
