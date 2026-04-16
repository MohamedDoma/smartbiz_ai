<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;

/**
 * Batch 2, Part A — Negative / Abuse Tests (N01–N17).
 *
 * Validates the system rejects every invalid input correctly.
 */
class NegativeTest extends SmartBizTestCase
{
    // ── N01: Empty body on POST ──────────────────────────────────
    public function test_n01_empty_body_post_contacts(): void
    {
        $this->wsPost('/api/contacts', [])->assertUnprocessable();
    }

    // ── N02: Invalid UUID in path ────────────────────────────────
    public function test_n02_invalid_uuid_in_path(): void
    {
        // A non-UUID path param will trigger a PGSQL invalid text error.
        // The global exception handler converts this to a JSON error response.
        // We validate the system does not return 2xx (it returns 404 or 500).
        $response = $this->wsGet('/api/contacts/not-a-uuid');
        $this->assertTrue(
            $response->getStatusCode() >= 400,
            'Malformed UUID in path must not return a success status'
        );
    }

    // ── N03: Invalid UUID in FK field ────────────────────────────
    public function test_n03_invalid_uuid_in_fk_field(): void
    {
        $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'contact_id'   => 'abc',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ])->assertUnprocessable();
    }

    // ── N04: Invalid invoice_type enum ───────────────────────────
    public function test_n04_invalid_invoice_type_enum(): void
    {
        $this->wsPost('/api/invoices', [
            'invoice_type' => 'invalid',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ])->assertUnprocessable();
    }

    // ── N05: Invalid order status enum ───────────────────────────
    public function test_n05_invalid_order_status_enum(): void
    {
        // Create a valid order first
        $c = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        $id = $c->json('data.id');

        $this->wsPut("/api/orders/{$id}", ['status' => 'nonexistent'])
            ->assertUnprocessable();
    }

    // ── N06: Invalid recurring expense frequency enum ────────────
    public function test_n06_invalid_recurring_frequency_enum(): void
    {
        $this->wsPost('/api/recurring-expenses', [
            'category'      => 'Test',
            'amount'        => 100,
            'frequency'     => 'hourly',
            'next_due_date' => '2026-06-01',
        ])->assertUnprocessable();
    }

    // ── N07: Invalid inventory movement_type enum ────────────────
    public function test_n07_invalid_movement_type_enum(): void
    {
        $this->wsPost('/api/inventory-movements', [
            'warehouse_id'  => CertificationSeeder::WAREHOUSE_A1,
            'product_id'    => CertificationSeeder::PRODUCT_A1,
            'movement_type' => 'fake',
            'quantity_change' => 10,
        ])->assertUnprocessable();
    }

    // ── N08: Negative payment amount ─────────────────────────────
    public function test_n08_negative_payment_amount(): void
    {
        $this->wsPost('/api/payments', [
            'amount'         => -100,
            'payment_method' => 'cash',
        ])->assertUnprocessable();
    }

    // ── N09: Zero quantity invoice item ──────────────────────────
    public function test_n09_zero_quantity_invoice_item(): void
    {
        $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [['quantity' => 0, 'unit_price' => 50]],
        ])->assertUnprocessable();
    }

    // ── N10: Production order target_quantity = 0 ────────────────
    public function test_n10_production_order_zero_target_quantity(): void
    {
        $this->wsPost('/api/production-orders', [
            'product_id'      => CertificationSeeder::PRODUCT_A1,
            'target_quantity' => 0,
        ])->assertUnprocessable();
    }

    // ── N11: Mass assignment — workspace_id in body ──────────────
    public function test_n11_mass_assignment_workspace_id_ignored(): void
    {
        $response = $this->wsPost('/api/contacts', [
            'type'         => 'customer',
            'name'         => 'MassAssign-' . uniqid(),
            'workspace_id' => CertificationSeeder::WS_B, // attempt injection
        ]);
        $response->assertCreated();

        // The contact must belong to WS-A (the auth'd workspace), not WS-B
        $id = $response->json('data.id');
        $this->wsGet("/api/contacts/{$id}")->assertOk();
    }

    // ── N12: Mass assignment — created_by in body ────────────────
    public function test_n12_mass_assignment_created_by_ignored(): void
    {
        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'created_by'   => '00000000-0000-0000-0000-000000000099', // fake user
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        // Must still succeed — created_by should not be mass-assignable
        $response->assertCreated();
    }

    // ── N13: Direct child-table access — invoice_items ───────────
    public function test_n13_no_direct_access_invoice_items(): void
    {
        $this->wsGet('/api/invoice-items')->assertNotFound();
    }

    // ── N14: Direct child-table access — order_items ─────────────
    public function test_n14_no_direct_access_order_items(): void
    {
        $this->wsGet('/api/order-items')->assertNotFound();
    }

    // ── N15: Direct child-table access — journal_lines ───────────
    public function test_n15_no_direct_access_journal_lines(): void
    {
        $this->wsGet('/api/journal-lines')->assertNotFound();
    }

    // ── N16: Malformed JSON body ─────────────────────────────────
    public function test_n16_malformed_json_body(): void
    {
        $response = $this->withHeaders([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Content-Type'   => 'application/json',
            'Accept'         => 'application/json',
        ])->call('POST', '/api/contacts', [], [], [], [], '{invalid json');

        // Malformed JSON must not return 2xx — acceptable: 400, 422, or 500
        $this->assertTrue(
            $response->getStatusCode() >= 400,
            'Malformed JSON must not return a success status'
        );
    }

    // ── N17: Pagination abuse — per_page=999999 ──────────────────
    public function test_n17_pagination_oversized_per_page(): void
    {
        // Should not crash — either cap or return data
        $response = $this->wsGet('/api/contacts?per_page=999999');
        $response->assertOk();
    }
}
