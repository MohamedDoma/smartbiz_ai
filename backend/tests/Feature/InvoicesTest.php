<?php

namespace Tests\Feature;

class InvoicesTest extends SmartBizTestCase
{
    public function test_create_invoice_with_items(): void
    {
        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [
                ['quantity' => 2, 'unit_price' => 50, 'product_name_snapshot' => 'Widget A'],
                ['quantity' => 1, 'unit_price' => 100, 'product_name_snapshot' => 'Service'],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.invoice_type', 'sale')
            ->assertJsonPath('data.total_amount', '200.00')
            ->assertJsonPath('data.payment_status', 'unpaid')
            ->assertJsonCount(2, 'data.items');
    }

    public function test_show_invoice_includes_items(): void
    {
        $c = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [['quantity' => 1, 'unit_price' => 75]],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/invoices/{$id}");
        $response->assertOk()
            ->assertJsonStructure(['data' => ['items']])
            ->assertJsonCount(1, 'data.items');
    }

    public function test_update_invoice_status(): void
    {
        $c = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/invoices/{$id}", ['payment_status' => 'paid']);
        $response->assertOk()->assertJsonPath('data.payment_status', 'paid');
    }

    public function test_list_invoices(): void
    {
        $response = $this->wsGet('/api/invoices');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_create_invoice_requires_items(): void
    {
        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [],
        ]);
        $response->assertUnprocessable();
    }
}
