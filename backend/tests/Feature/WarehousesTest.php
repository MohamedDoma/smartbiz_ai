<?php

namespace Tests\Feature;

class WarehousesTest extends SmartBizTestCase
{
    public function test_create_warehouse(): void
    {
        $response = $this->wsPost('/api/warehouses', [
            'name'     => 'Test Warehouse ' . uniqid(),
            'location' => 'Floor 1',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.location', 'Floor 1')
            ->assertJsonStructure(['data' => ['id', 'name', 'location']]);
    }

    public function test_list_warehouses(): void
    {
        $this->wsPost('/api/warehouses', ['name' => 'ListWH ' . uniqid()]);
        $response = $this->wsGet('/api/warehouses');
        $response->assertOk()->assertJsonStructure(['data']);
    }

    public function test_show_warehouse(): void
    {
        $c = $this->wsPost('/api/warehouses', ['name' => 'ShowWH ' . uniqid()]);
        $id = $c->json('data.id');
        $response = $this->wsGet("/api/warehouses/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_warehouse(): void
    {
        $c = $this->wsPost('/api/warehouses', ['name' => 'Before ' . uniqid()]);
        $id = $c->json('data.id');
        $response = $this->wsPut("/api/warehouses/{$id}", ['name' => 'After-' . uniqid()]);
        $response->assertOk();
    }

    public function test_delete_warehouse(): void
    {
        $c = $this->wsPost('/api/warehouses', ['name' => 'DelWH ' . uniqid()]);
        $id = $c->json('data.id');
        $this->wsDelete("/api/warehouses/{$id}")->assertOk();
        $this->wsGet("/api/warehouses/{$id}")->assertNotFound();
    }

    public function test_duplicate_name_returns_409(): void
    {
        $name = 'UniqueName ' . uniqid();
        $this->wsPost('/api/warehouses', ['name' => $name]);
        $response = $this->wsPost('/api/warehouses', ['name' => $name]);
        $response->assertStatus(409);
    }
}
