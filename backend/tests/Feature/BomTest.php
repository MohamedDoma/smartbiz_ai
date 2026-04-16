<?php

namespace Tests\Feature;

class BomTest extends SmartBizTestCase
{
    private function createTwoProducts(): array
    {
        $final = $this->wsPost('/api/products', [
            'name' => 'Final ' . uniqid(),
            'sku'  => 'FP-' . uniqid(),
            'base_price' => 100,
        ]);
        $raw = $this->wsPost('/api/products', [
            'name' => 'Raw ' . uniqid(),
            'sku'  => 'RM-' . uniqid(),
            'base_price' => 10,
        ]);
        return ['final' => $final->json('data.id'), 'raw' => $raw->json('data.id')];
    }

    public function test_create_bom_entry(): void
    {
        $p = $this->createTwoProducts();
        $response = $this->wsPost('/api/bom', [
            'final_product_id'  => $p['final'],
            'raw_material_id'   => $p['raw'],
            'quantity_required' => 3.5,
        ]);
        $response->assertCreated()
            ->assertJsonPath('data.quantity_required', '3.5000')
            ->assertJsonPath('data.final_product_id', $p['final']);
    }

    public function test_list_bom(): void
    {
        $response = $this->wsGet('/api/bom');
        $response->assertOk()->assertJsonStructure(['data']);
    }

    public function test_show_bom(): void
    {
        $p = $this->createTwoProducts();
        $c = $this->wsPost('/api/bom', [
            'final_product_id' => $p['final'],
            'raw_material_id'  => $p['raw'],
            'quantity_required' => 2,
        ]);
        $id = $c->json('data.id');
        $response = $this->wsGet("/api/bom/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_bom_quantity(): void
    {
        $p = $this->createTwoProducts();
        $c = $this->wsPost('/api/bom', [
            'final_product_id' => $p['final'],
            'raw_material_id'  => $p['raw'],
            'quantity_required' => 5,
        ]);
        $id = $c->json('data.id');
        $response = $this->wsPut("/api/bom/{$id}", ['quantity_required' => 10]);
        $response->assertOk()->assertJsonPath('data.quantity_required', '10.0000');
    }

    public function test_delete_bom(): void
    {
        $p = $this->createTwoProducts();
        $c = $this->wsPost('/api/bom', [
            'final_product_id' => $p['final'],
            'raw_material_id'  => $p['raw'],
            'quantity_required' => 1,
        ]);
        $id = $c->json('data.id');
        $this->wsDelete("/api/bom/{$id}")->assertOk();
        $this->wsGet("/api/bom/{$id}")->assertNotFound();
    }

    public function test_duplicate_material_returns_409(): void
    {
        $p = $this->createTwoProducts();
        $this->wsPost('/api/bom', [
            'final_product_id' => $p['final'],
            'raw_material_id'  => $p['raw'],
            'quantity_required' => 1,
        ]);
        $response = $this->wsPost('/api/bom', [
            'final_product_id' => $p['final'],
            'raw_material_id'  => $p['raw'],
            'quantity_required' => 5,
        ]);
        $response->assertStatus(409);
    }
}
