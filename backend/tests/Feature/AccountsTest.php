<?php

namespace Tests\Feature;

class AccountsTest extends SmartBizTestCase
{
    public function test_create_account(): void
    {
        $response = $this->wsPost('/api/accounts', [
            'code' => 'T' . uniqid(),
            'name' => 'Test Account',
            'type' => 'asset',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'Test Account')
            ->assertJsonPath('data.type', 'asset');
    }

    public function test_create_child_account(): void
    {
        $parent = $this->wsPost('/api/accounts', [
            'code' => 'P' . uniqid(), 'name' => 'Parent', 'type' => 'asset',
        ]);
        $parentId = $parent->json('data.id');

        $child = $this->wsPost('/api/accounts', [
            'code' => 'C' . uniqid(), 'name' => 'Child', 'type' => 'asset',
            'parent_id' => $parentId,
        ]);

        $child->assertCreated()->assertJsonPath('data.parent_id', $parentId);
    }

    public function test_list_accounts_tree(): void
    {
        $code = 'R' . uniqid();
        $parent = $this->wsPost('/api/accounts', [
            'code' => $code, 'name' => 'Root', 'type' => 'equity',
        ]);
        $parentId = $parent->json('data.id');

        $this->wsPost('/api/accounts', [
            'code' => $code . '.1', 'name' => 'Leaf', 'type' => 'equity',
            'parent_id' => $parentId,
        ]);

        $response = $this->wsGet('/api/accounts');
        $response->assertOk();

        // Find the root we created and check it has children
        $root = collect($response->json('data'))->where('id', $parentId)->first();
        $this->assertNotNull($root, 'Root account should appear in list');
        $this->assertNotEmpty($root['children'], 'Root should have children');
    }

    public function test_delete_account(): void
    {
        $c = $this->wsPost('/api/accounts', [
            'code' => 'D' . uniqid(), 'name' => 'Delete Me', 'type' => 'expense',
        ]);
        $id = $c->json('data.id');

        $this->wsDelete("/api/accounts/{$id}")->assertOk();
        $this->wsGet("/api/accounts/{$id}")->assertNotFound();
    }
}
