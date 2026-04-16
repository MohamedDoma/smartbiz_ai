<?php

namespace Tests\Feature;

class ProductionOrdersTest extends SmartBizTestCase
{
    private function createProduct(): string
    {
        $r = $this->wsPost('/api/products', [
            'name' => 'PO-Prod ' . uniqid(),
            'sku'  => 'PO-' . uniqid(),
            'base_price' => 55,
        ]);
        return $r->json('data.id');
    }

    public function test_create_production_order(): void
    {
        $prodId = $this->createProduct();
        $response = $this->wsPost('/api/production-orders', [
            'product_id'      => $prodId,
            'target_quantity' => 100,
            'start_date'      => '2026-05-01',
            'end_date'        => '2026-05-15',
        ]);
        $response->assertCreated()
            ->assertJsonPath('data.status', 'planned')
            ->assertJsonPath('data.target_quantity', '100.0000');
    }

    public function test_list_production_orders(): void
    {
        $response = $this->wsGet('/api/production-orders');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_show_production_order(): void
    {
        $prodId = $this->createProduct();
        $c = $this->wsPost('/api/production-orders', [
            'product_id' => $prodId,
            'target_quantity' => 50,
        ]);
        $id = $c->json('data.id');
        $response = $this->wsGet("/api/production-orders/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_production_order_status(): void
    {
        $prodId = $this->createProduct();
        $c = $this->wsPost('/api/production-orders', [
            'product_id' => $prodId,
            'target_quantity' => 25,
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/production-orders/{$id}", ['status' => 'in_progress']);
        $response->assertOk()->assertJsonPath('data.status', 'in_progress');

        $response = $this->wsPut("/api/production-orders/{$id}", ['status' => 'done']);
        $response->assertOk()->assertJsonPath('data.status', 'done');
    }

    /** F11 — Cancel a production order */
    public function test_cancel_production_order(): void
    {
        $prodId = $this->createProduct();
        $c = $this->wsPost('/api/production-orders', [
            'product_id'      => $prodId,
            'target_quantity' => 10,
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/production-orders/{$id}", ['status' => 'cancelled']);
        $response->assertOk()->assertJsonPath('data.status', 'cancelled');
    }
}
