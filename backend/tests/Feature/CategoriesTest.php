<?php

namespace Tests\Feature;

/**
 * F01–F06: Product Categories functional tests.
 */
class CategoriesTest extends SmartBizTestCase
{
    /** F01 */
    public function test_create_category(): void
    {
        $response = $this->wsPost('/api/product-categories', [
            'name' => 'Batch1-Cat-' . uniqid(),
        ]);
        $response->assertCreated()
            ->assertJsonStructure(['data' => ['id', 'name']]);
    }

    /** F02 */
    public function test_list_categories(): void
    {
        $response = $this->wsGet('/api/product-categories');
        $response->assertOk()
            ->assertJsonStructure(['data']);
    }

    /** F03 */
    public function test_show_category(): void
    {
        $c = $this->wsPost('/api/product-categories', ['name' => 'ShowCat-' . uniqid()]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/product-categories/{$id}");
        $response->assertOk()
            ->assertJsonPath('data.id', $id);
    }

    /** F04 */
    public function test_update_category(): void
    {
        $c = $this->wsPost('/api/product-categories', ['name' => 'Before-' . uniqid()]);
        $id = $c->json('data.id');
        $newName = 'After-' . uniqid();

        $response = $this->wsPut("/api/product-categories/{$id}", ['name' => $newName]);
        $response->assertOk()
            ->assertJsonPath('data.name', $newName);
    }

    /** F05 */
    public function test_delete_category(): void
    {
        $c = $this->wsPost('/api/product-categories', ['name' => 'DeleteMe-' . uniqid()]);
        $id = $c->json('data.id');

        $this->wsDelete("/api/product-categories/{$id}")->assertOk();
        $this->wsGet("/api/product-categories/{$id}")->assertNotFound();
    }

    /** F06 */
    public function test_create_child_category_hierarchy(): void
    {
        $parent = $this->wsPost('/api/product-categories', ['name' => 'Parent-' . uniqid()]);
        $parentId = $parent->json('data.id');

        $child = $this->wsPost('/api/product-categories', [
            'name'      => 'Child-' . uniqid(),
            'parent_id' => $parentId,
        ]);
        $child->assertCreated()
            ->assertJsonPath('data.parent_id', $parentId);
    }
}
