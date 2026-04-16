<?php

namespace Tests\Feature;

class InventoryTest extends SmartBizTestCase
{
    private function createWarehouse(): string
    {
        $r = $this->wsPost('/api/warehouses', ['name' => 'IWH-' . uniqid()]);
        return $r->json('data.id');
    }

    private function createProduct(): string
    {
        $r = $this->wsPost('/api/products', [
            'name' => 'InvProd ' . uniqid(),
            'sku'  => 'INV-' . uniqid(),
            'base_price' => 10,
        ]);
        return $r->json('data.id');
    }

    public function test_create_inventory_movement_purchase(): void
    {
        $whId = $this->createWarehouse();
        $prodId = $this->createProduct();

        $response = $this->wsPost('/api/inventory-movements', [
            'warehouse_id'   => $whId,
            'product_id'     => $prodId,
            'movement_type'  => 'purchase_receipt',
            'quantity_change' => 100,
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.movement_type', 'purchase_receipt')
            ->assertJsonPath('data.quantity_before', '0.00')
            ->assertJsonPath('data.quantity_after', '100.00')
            ->assertJsonPath('data.quantity_change', '100.00');
    }

    public function test_create_inventory_movement_sale(): void
    {
        $whId = $this->createWarehouse();
        $prodId = $this->createProduct();

        // First add stock
        $this->wsPost('/api/inventory-movements', [
            'warehouse_id' => $whId, 'product_id' => $prodId,
            'movement_type' => 'opening_balance', 'quantity_change' => 50,
        ]);

        // Then sell
        $response = $this->wsPost('/api/inventory-movements', [
            'warehouse_id' => $whId, 'product_id' => $prodId,
            'movement_type' => 'sale_shipment', 'quantity_change' => 20,
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.quantity_before', '50.00')
            ->assertJsonPath('data.quantity_after', '30.00')
            ->assertJsonPath('data.quantity_change', '-20.00');
    }

    public function test_insufficient_stock_returns_422(): void
    {
        $whId = $this->createWarehouse();
        $prodId = $this->createProduct();

        $response = $this->wsPost('/api/inventory-movements', [
            'warehouse_id' => $whId, 'product_id' => $prodId,
            'movement_type' => 'sale_shipment', 'quantity_change' => 10,
        ]);

        $response->assertUnprocessable()
            ->assertJsonPath('error', 'insufficient_stock');
    }

    public function test_list_movements(): void
    {
        $response = $this->wsGet('/api/inventory-movements');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_show_movement(): void
    {
        $whId = $this->createWarehouse();
        $prodId = $this->createProduct();
        $c = $this->wsPost('/api/inventory-movements', [
            'warehouse_id' => $whId, 'product_id' => $prodId,
            'movement_type' => 'opening_balance', 'quantity_change' => 10,
        ]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/inventory-movements/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_inventory_levels(): void
    {
        $whId = $this->createWarehouse();
        $prodId = $this->createProduct();

        $this->wsPost('/api/inventory-movements', [
            'warehouse_id' => $whId, 'product_id' => $prodId,
            'movement_type' => 'opening_balance', 'quantity_change' => 75,
        ]);

        $response = $this->wsGet('/api/inventory-movements/levels');
        $response->assertOk()->assertJsonStructure(['data']);

        // Find the product we just stocked
        $found = collect($response->json('data'))
            ->where('product_id', $prodId)
            ->where('warehouse_id', $whId)
            ->first();

        $this->assertNotNull($found, 'Product should appear in levels');
        $this->assertEquals(75, $found['current_stock']);
    }
}
