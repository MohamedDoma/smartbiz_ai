<?php

namespace Tests\Feature;

class StockReservationsTest extends SmartBizTestCase
{
    private function createPrerequisites(): array
    {
        $wh = $this->wsPost('/api/warehouses', ['name' => 'RWH-' . uniqid()]);
        $prod = $this->wsPost('/api/products', [
            'name' => 'RProd ' . uniqid(),
            'sku' => 'RES-' . uniqid(),
            'base_price' => 10,
        ]);

        // Create order to link reservation to
        $order = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 5, 'unit_price' => 10, 'product_name_snapshot' => 'Res Product']],
        ]);

        return [
            'warehouse_id' => $wh->json('data.id'),
            'product_id' => $prod->json('data.id'),
            'order_id' => $order->json('data.id'),
            'order_item_id' => $order->json('data.items.0.id'),
        ];
    }

    public function test_create_reservation(): void
    {
        $pre = $this->createPrerequisites();

        $response = $this->wsPost('/api/stock-reservations', [
            'order_id'          => $pre['order_id'],
            'order_item_id'     => $pre['order_item_id'],
            'warehouse_id'      => $pre['warehouse_id'],
            'product_id'        => $pre['product_id'],
            'reserved_quantity' => 5,
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.reserved_quantity', '5.00')
            ->assertJsonPath('data.fulfilled_quantity', '0.00');
    }

    public function test_list_reservations(): void
    {
        $response = $this->wsGet('/api/stock-reservations');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_release_reservation(): void
    {
        $pre = $this->createPrerequisites();
        $c = $this->wsPost('/api/stock-reservations', [
            'order_id' => $pre['order_id'],
            'order_item_id' => $pre['order_item_id'],
            'warehouse_id' => $pre['warehouse_id'],
            'product_id' => $pre['product_id'],
            'reserved_quantity' => 3,
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPost("/api/stock-reservations/{$id}/release");
        $response->assertOk()
            ->assertJsonPath('data.status', 'released')
            ->assertJsonPath('data.released_quantity', '3.00');
    }

    public function test_fulfill_reservation(): void
    {
        $pre = $this->createPrerequisites();
        $c = $this->wsPost('/api/stock-reservations', [
            'order_id' => $pre['order_id'],
            'order_item_id' => $pre['order_item_id'],
            'warehouse_id' => $pre['warehouse_id'],
            'product_id' => $pre['product_id'],
            'reserved_quantity' => 10,
        ]);
        $id = $c->json('data.id');

        // Partial fulfill
        $response = $this->wsPost("/api/stock-reservations/{$id}/fulfill", [
            'quantity' => 4,
        ]);
        $response->assertOk()
            ->assertJsonPath('data.status', 'partially_fulfilled')
            ->assertJsonPath('data.fulfilled_quantity', '4.00');

        // Full fulfill
        $response = $this->wsPost("/api/stock-reservations/{$id}/fulfill", [
            'quantity' => 6,
        ]);
        $response->assertOk()
            ->assertJsonPath('data.status', 'fulfilled')
            ->assertJsonPath('data.fulfilled_quantity', '10.00');
    }

    public function test_cannot_release_already_released(): void
    {
        $pre = $this->createPrerequisites();
        $c = $this->wsPost('/api/stock-reservations', [
            'order_id' => $pre['order_id'],
            'order_item_id' => $pre['order_item_id'],
            'warehouse_id' => $pre['warehouse_id'],
            'product_id' => $pre['product_id'],
            'reserved_quantity' => 1,
        ]);
        $id = $c->json('data.id');

        $this->wsPost("/api/stock-reservations/{$id}/release");
        $response = $this->wsPost("/api/stock-reservations/{$id}/release");
        $response->assertUnprocessable();
    }
}
