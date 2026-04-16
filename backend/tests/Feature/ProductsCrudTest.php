<?php

namespace Tests\Feature;

class ProductsCrudTest extends SmartBizTestCase
{
    public function test_create_product(): void
    {
        $response = $this->wsPost('/api/products', [
            'name'       => 'PHPUnit Widget',
            'sku'        => 'PHPUnit-' . uniqid(),
            'base_price' => 99.99,
            'cost_price' => 50.00,
            'type'       => 'physical',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'PHPUnit Widget')
            ->assertJsonPath('data.base_price', '99.99')
            ->assertJsonStructure(['data' => ['id', 'sku', 'type', 'base_price']]);
    }

    public function test_list_products(): void
    {
        $response = $this->wsGet('/api/products');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_show_product(): void
    {
        $c = $this->wsPost('/api/products', ['name' => 'ShowP', 'base_price' => 10, 'sku' => 'SHOW-' . uniqid()]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/products/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_product(): void
    {
        $c = $this->wsPost('/api/products', ['name' => 'Before', 'base_price' => 10, 'sku' => 'UPD-' . uniqid()]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/products/{$id}", ['name' => 'After', 'base_price' => 20]);
        $response->assertOk()
            ->assertJsonPath('data.name', 'After')
            ->assertJsonPath('data.base_price', '20.00');
    }

    public function test_soft_delete_product(): void
    {
        $c = $this->wsPost('/api/products', ['name' => 'SoftDel', 'base_price' => 10, 'sku' => 'DEL-' . uniqid()]);
        $id = $c->json('data.id');

        $this->wsDelete("/api/products/{$id}")->assertOk();
        // Product should no longer appear in list (is_deleted = true)
        $list = $this->wsGet('/api/products?search=SoftDel');
        $found = collect($list->json('data'))->where('id', $id)->count();
        $this->assertEquals(0, $found, 'Soft-deleted product should not appear in list');
    }

    public function test_duplicate_sku_returns_409(): void
    {
        $sku = 'DUP-' . uniqid();
        $this->wsPost('/api/products', ['name' => 'First', 'base_price' => 10, 'sku' => $sku]);
        $response = $this->wsPost('/api/products', ['name' => 'Second', 'base_price' => 10, 'sku' => $sku]);

        $response->assertStatus(409)
            ->assertJsonPath('error', 'duplicate_entry');
    }
}
