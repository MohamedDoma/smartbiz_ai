<?php

namespace Tests\Feature;

class OrdersTest extends SmartBizTestCase
{
    public function test_create_order_with_items(): void
    {
        $response = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [
                ['quantity' => 3, 'unit_price' => 25, 'product_name_snapshot' => 'Widget'],
                ['quantity' => 1, 'unit_price' => 100, 'product_name_snapshot' => 'Premium'],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.order_type', 'sale_order')
            ->assertJsonPath('data.status', 'draft')
            ->assertJsonPath('data.total_amount', '175.00')
            ->assertJsonCount(2, 'data.items');
    }

    public function test_show_order_with_items(): void
    {
        $c = $this->wsPost('/api/orders', [
            'order_type' => 'quote',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/orders/{$id}");
        $response->assertOk()
            ->assertJsonStructure(['data' => ['items']])
            ->assertJsonCount(1, 'data.items');
    }

    public function test_update_order_status(): void
    {
        $c = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/orders/{$id}", ['status' => 'confirmed']);
        $response->assertOk()->assertJsonPath('data.status', 'confirmed');
    }

    public function test_list_orders(): void
    {
        $response = $this->wsGet('/api/orders');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }
}
