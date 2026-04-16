<?php

namespace Tests\Feature;

class ContactsCrudTest extends SmartBizTestCase
{
    public function test_create_contact(): void
    {
        $response = $this->wsPost('/api/contacts', [
            'type'  => 'customer',
            'name'  => 'Test Customer PHPUnit',
            'email' => 'phpunit@test.test',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'Test Customer PHPUnit')
            ->assertJsonPath('data.type', 'customer')
            ->assertJsonStructure(['data' => ['id', 'type', 'name', 'email', 'created_at']]);
    }

    public function test_list_contacts(): void
    {
        $this->wsPost('/api/contacts', ['type' => 'supplier', 'name' => 'List Test']);
        $response = $this->wsGet('/api/contacts');

        $response->assertOk()
            ->assertJsonStructure(['data', 'meta' => ['current_page', 'total']]);
    }

    public function test_show_contact(): void
    {
        $created = $this->wsPost('/api/contacts', ['type' => 'customer', 'name' => 'Show Test']);
        $id = $created->json('data.id');

        $response = $this->wsGet("/api/contacts/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_contact(): void
    {
        $created = $this->wsPost('/api/contacts', ['type' => 'customer', 'name' => 'Before']);
        $id = $created->json('data.id');

        $response = $this->wsPut("/api/contacts/{$id}", ['name' => 'After']);
        $response->assertOk()->assertJsonPath('data.name', 'After');
    }

    public function test_delete_contact(): void
    {
        $created = $this->wsPost('/api/contacts', ['type' => 'customer', 'name' => 'DeleteMe']);
        $id = $created->json('data.id');

        $response = $this->wsDelete("/api/contacts/{$id}");
        $response->assertOk()->assertJsonPath('message', 'Contact deleted.');

        $this->wsGet("/api/contacts/{$id}")->assertNotFound();
    }

    public function test_create_contact_validation_fails(): void
    {
        $response = $this->wsPost('/api/contacts', []);
        $response->assertUnprocessable();
    }
}
