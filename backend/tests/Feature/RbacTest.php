<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;

/**
 * Batch 2, Part B — RBAC Permission Tests (R01–R14).
 *
 * Uses CertificationSeeder roles:
 *   readonly  — list/show only
 *   finance   — invoices, payments, accounts, JE, recurring, reports
 *   warehouse — warehouses, inventory, reservations, products (read)
 *   sales     — contacts, orders, invoices, payments (read), products (read)
 *   noperm    — zero permissions (403 baseline)
 *   manager   — all except critical deletes
 */
class RbacTest extends SmartBizTestCase
{
    // ── Helper: login as a certification user ─────────────────────

    /**
     * Obtain a Sanctum token for a certification user.
     */
    private function loginAs(string $email): string
    {
        $response = $this->postJson('/api/auth/login', [
            'email'    => $email,
            'password' => CertificationSeeder::PASSWORD,
        ]);
        $response->assertOk();
        return $response->json('token');
    }

    /**
     * Make a workspace-scoped GET as a specific user.
     */
    private function wsGetAs(string $email, string $uri, string $wsId = null): \Illuminate\Testing\TestResponse
    {
        $token = $this->loginAs($email);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId ?? CertificationSeeder::WS_A,
            'Accept'         => 'application/json',
        ])->getJson($uri);
    }

    /**
     * Make a workspace-scoped POST as a specific user.
     */
    private function wsPostAs(string $email, string $uri, array $data = [], string $wsId = null): \Illuminate\Testing\TestResponse
    {
        $token = $this->loginAs($email);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId ?? CertificationSeeder::WS_A,
            'Accept'         => 'application/json',
        ])->postJson($uri, $data);
    }

    /**
     * Make a workspace-scoped DELETE as a specific user.
     */
    private function wsDeleteAs(string $email, string $uri, string $wsId = null): \Illuminate\Testing\TestResponse
    {
        $token = $this->loginAs($email);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId ?? CertificationSeeder::WS_A,
            'Accept'         => 'application/json',
        ])->deleteJson($uri);
    }

    // ── R01: Readonly can list contacts ──────────────────────────

    public function test_r01_readonly_can_list_contacts(): void
    {
        $this->wsGetAs('readonly@cert.test', '/api/contacts')->assertOk();
    }

    // ── R02: Readonly cannot create contacts ─────────────────────

    public function test_r02_readonly_cannot_create_contacts(): void
    {
        $this->wsPostAs('readonly@cert.test', '/api/contacts', [
            'type' => 'customer',
            'name' => 'Should Fail',
        ])->assertForbidden();
    }

    // ── R03: Readonly cannot delete contacts ─────────────────────

    public function test_r03_readonly_cannot_delete_contacts(): void
    {
        $this->wsDeleteAs('readonly@cert.test', '/api/contacts/' . CertificationSeeder::CONTACT_A1)
            ->assertForbidden();
    }

    // ── R04: Finance can create payments ─────────────────────────

    public function test_r04_finance_can_create_payments(): void
    {
        $response = $this->wsPostAs('finance@cert.test', '/api/payments', [
            'amount'         => 25.00,
            'payment_method' => 'cash',
        ]);
        $this->assertContains($response->getStatusCode(), [200, 201]);
    }

    // ── R05: Finance cannot create contacts ──────────────────────

    public function test_r05_finance_cannot_create_contacts(): void
    {
        $this->wsPostAs('finance@cert.test', '/api/contacts', [
            'type' => 'customer',
            'name' => 'Should Fail',
        ])->assertForbidden();
    }

    // ── R06: Warehouse can create inventory movements ────────────

    public function test_r06_warehouse_can_create_inventory_movements(): void
    {
        $response = $this->wsPostAs('warehouse@cert.test', '/api/inventory-movements', [
            'warehouse_id'    => CertificationSeeder::WAREHOUSE_A1,
            'product_id'      => CertificationSeeder::PRODUCT_A1,
            'movement_type'   => 'purchase_receipt',
            'quantity_change'  => 10,
        ]);
        $response->assertCreated();
    }

    // ── R07: Warehouse cannot access reports ─────────────────────

    public function test_r07_warehouse_cannot_access_reports(): void
    {
        $this->wsGetAs('warehouse@cert.test', '/api/reports/sales')
            ->assertForbidden();
    }

    // ── R08: Sales can create invoices ───────────────────────────

    public function test_r08_sales_can_create_invoices(): void
    {
        $this->wsPostAs('sales@cert.test', '/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [['quantity' => 1, 'unit_price' => 50]],
        ])->assertCreated();
    }

    // ── R09: Sales cannot create payments ────────────────────────

    public function test_r09_sales_cannot_create_payments(): void
    {
        $this->wsPostAs('sales@cert.test', '/api/payments', [
            'amount'         => 10.00,
            'payment_method' => 'cash',
        ])->assertForbidden();
    }

    // ── R10: NoPerm gets 403 on GET /contacts ────────────────────

    public function test_r10_noperm_cannot_list_contacts(): void
    {
        $this->wsGetAs('noperm@cert.test', '/api/contacts')
            ->assertForbidden();
    }

    // ── R11: NoPerm gets 403 on POST /products ───────────────────

    public function test_r11_noperm_cannot_create_products(): void
    {
        $this->wsPostAs('noperm@cert.test', '/api/products', [
            'name' => 'Nope',
            'sku'  => 'NOPE-' . uniqid(),
            'base_price' => 10,
        ])->assertForbidden();
    }

    // ── R12: NoPerm gets 403 on GET /reports ─────────────────────

    public function test_r12_noperm_cannot_access_reports(): void
    {
        $this->wsGetAs('noperm@cert.test', '/api/reports/sales')
            ->assertForbidden();
    }

    // ── R13: Manager can create but not delete categories ────────

    public function test_r13_manager_can_create_but_not_delete_categories(): void
    {
        // Create should succeed
        $response = $this->wsPostAs('manager@cert.test', '/api/product-categories', [
            'name' => 'MgrCat-' . uniqid(),
        ]);
        $response->assertCreated();
        $id = $response->json('data.id');

        // Delete should be forbidden (manager lacks categories.delete)
        $this->wsDeleteAs('manager@cert.test', "/api/product-categories/{$id}")
            ->assertForbidden();
    }

    // ── R14: Manager can create but not delete accounts ──────────

    public function test_r14_manager_can_create_but_not_delete_accounts(): void
    {
        // Create should succeed
        $response = $this->wsPostAs('manager@cert.test', '/api/accounts', [
            'code' => 'MGR-' . uniqid(),
            'name' => 'Manager Account',
            'type' => 'asset',
        ]);
        $response->assertCreated();
        $id = $response->json('data.id');

        // Delete should be forbidden (manager lacks accounts.delete)
        $this->wsDeleteAs('manager@cert.test', "/api/accounts/{$id}")
            ->assertForbidden();
    }
}
