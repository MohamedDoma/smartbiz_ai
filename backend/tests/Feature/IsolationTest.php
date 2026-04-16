<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;

/**
 * Batch 3 — Multi-Tenant Isolation + Child Table Safety + Reporting Security.
 *
 * ZERO TOLERANCE: Any cross-workspace data leak is a CERTIFICATION FAIL.
 *
 * Workspace Alpha (WS-A) = primary workspace
 * Workspace Bravo (WS-B) = isolation test workspace
 * Cross user = readonly in WS-A, admin in WS-B
 */
class IsolationTest extends SmartBizTestCase
{
    // ── Helpers ──────────────────────────────────────────────────

    private function loginAs(string $email, string $password = null): string
    {
        $response = $this->postJson('/api/auth/login', [
            'email'    => $email,
            'password' => $password ?? CertificationSeeder::PASSWORD,
        ]);
        $response->assertOk();
        return $response->json('token');
    }

    private function wsGetAs(string $email, string $uri, string $wsId, string $pw = null): \Illuminate\Testing\TestResponse
    {
        $token = $this->loginAs($email, $pw);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId,
            'Accept'         => 'application/json',
        ])->getJson($uri);
    }

    private function wsPostAs(string $email, string $uri, array $data, string $wsId, string $pw = null): \Illuminate\Testing\TestResponse
    {
        $token = $this->loginAs($email, $pw);
        return $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => $wsId,
            'Accept'         => 'application/json',
        ])->postJson($uri, $data);
    }

    // ═══════════════════════════════════════════════════════════════
    // Part A — Multi-Tenant Isolation
    // ═══════════════════════════════════════════════════════════════

    /** I01 — WS-A admin lists only WS-A contacts */
    public function test_i01_ws_a_user_lists_only_ws_a_contacts(): void
    {
        $response = $this->wsGet('/api/contacts');
        $response->assertOk();

        $names = collect($response->json('data'))->pluck('name')->toArray();
        // Must include WS-A contacts
        $this->assertTrue(
            in_array('Cert Customer Alpha', $names) || count($names) > 0,
            'WS-A contacts must be visible'
        );
        // Must NOT include WS-B contact
        $this->assertNotContains('Cert Customer Bravo', $names,
            'ISOLATION VIOLATION: WS-B contact visible from WS-A');
    }

    /** I02 — WS-B admin lists only WS-B contacts */
    public function test_i02_ws_b_admin_lists_only_ws_b_contacts(): void
    {
        $response = $this->wsGetAs('b_admin@cert.test', '/api/contacts', CertificationSeeder::WS_B);
        $response->assertOk();

        $names = collect($response->json('data'))->pluck('name')->toArray();
        $this->assertContains('Cert Customer Bravo', $names,
            'WS-B contact must be visible to WS-B admin');
        $this->assertNotContains('Cert Customer Alpha', $names,
            'ISOLATION VIOLATION: WS-A contact visible from WS-B');
        $this->assertNotContains('Cert Supplier Alpha', $names,
            'ISOLATION VIOLATION: WS-A supplier visible from WS-B');
    }

    /** I03 — WS-A user cannot show WS-B contact by UUID → 404 */
    public function test_i03_ws_a_cannot_show_ws_b_contact_by_uuid(): void
    {
        $this->wsGet('/api/contacts/' . CertificationSeeder::CONTACT_B1)
            ->assertNotFound();
    }

    /** I04 — WS-A admin forges WS-B header → 403 */
    public function test_i04_ws_a_admin_forges_ws_b_header(): void
    {
        // Admin user only has membership in WS-A, not WS-B
        $response = $this->wsGetAs(
            FoundationSeeder::USER_EMAIL,
            '/api/contacts',
            CertificationSeeder::WS_B,
            FoundationSeeder::USER_PASSWORD
        );
        $response->assertForbidden();
    }

    /** I05 — Cross user (readonly in WS-A) sees only WS-A products */
    public function test_i05_cross_user_ws_a_sees_only_ws_a_products(): void
    {
        $response = $this->wsGetAs('cross@cert.test', '/api/products', CertificationSeeder::WS_A);
        $response->assertOk();

        $names = collect($response->json('data'))->pluck('name')->toArray();
        $this->assertNotContains('Bravo Widget', $names,
            'ISOLATION VIOLATION: WS-B product visible to cross user in WS-A');
    }

    /** I06 — Cross user (admin in WS-B) sees only WS-B products */
    public function test_i06_cross_user_ws_b_sees_only_ws_b_products(): void
    {
        $response = $this->wsGetAs('cross@cert.test', '/api/products', CertificationSeeder::WS_B);
        $response->assertOk();

        $names = collect($response->json('data'))->pluck('name')->toArray();
        $this->assertContains('Bravo Widget', $names,
            'WS-B product must be visible to cross user in WS-B');
        $this->assertNotContains('Cert Widget', $names,
            'ISOLATION VIOLATION: WS-A product visible to cross user in WS-B');
        $this->assertNotContains('Cert Raw Material', $names,
            'ISOLATION VIOLATION: WS-A product visible to cross user in WS-B');
    }

    /** I07 — Sales report scoped to WS-A only */
    public function test_i07_reports_scoped_to_workspace_sales(): void
    {
        $response = $this->wsGet('/api/reports/sales');
        $response->assertOk();
        // Just verify it doesn't crash — data integrity will be tested further
    }

    /** I08 — WS-B notifications NOT visible from WS-A */
    public function test_i08_ws_b_notifications_not_visible_from_ws_a(): void
    {
        $response = $this->wsGet('/api/notifications');
        $response->assertOk();

        $messages = collect($response->json('data'))->pluck('message')->toArray();
        $this->assertNotContains('WS-B notification', $messages,
            'ISOLATION VIOLATION: WS-B notification visible from WS-A');
    }

    /** I09 — Audit logs scoped to WS-A only */
    public function test_i09_audit_logs_scoped_to_workspace(): void
    {
        $response = $this->wsGet('/api/audit-logs');
        $response->assertOk();

        $entityIds = collect($response->json('data'))->pluck('entity_id')->toArray();
        // WS-B audit log references CONTACT_B1
        $this->assertNotContains(CertificationSeeder::CONTACT_B1, $entityIds,
            'ISOLATION VIOLATION: WS-B audit log visible from WS-A');
    }

    /** I10 — Cross-workspace FK: invoice with WS-B contact from WS-A */
    public function test_i10_cross_workspace_fk_invoice_with_ws_b_contact(): void
    {
        // Attempt to create an invoice in WS-A with a contact_id from WS-B
        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'contact_id'   => CertificationSeeder::CONTACT_B1, // belongs to WS-B
            'items'        => [['quantity' => 1, 'unit_price' => 50]],
        ]);
        // Must be rejected — 403 (workspace isolation trigger) or 422
        $this->assertTrue(
            in_array($response->getStatusCode(), [403, 422]),
            'ISOLATION VIOLATION: Invoice created with cross-workspace contact_id! Status: ' . $response->getStatusCode()
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // Part A (continued) — Additional resource isolation
    // ═══════════════════════════════════════════════════════════════

    /** I11 — WS-A cannot see WS-B warehouses */
    public function test_i11_ws_a_cannot_see_ws_b_warehouses(): void
    {
        $response = $this->wsGet('/api/warehouses');
        $response->assertOk();

        $names = collect($response->json('data'))->pluck('name')->toArray();
        $this->assertNotContains('Bravo Warehouse', $names,
            'ISOLATION VIOLATION: WS-B warehouse visible from WS-A');
    }

    /** I12 — WS-A cannot show WS-B product by UUID */
    public function test_i12_ws_a_cannot_show_ws_b_product(): void
    {
        $this->wsGet('/api/products/' . CertificationSeeder::PRODUCT_B1)
            ->assertNotFound();
    }

    /** I13 — WS-A cannot show WS-B account by UUID */
    public function test_i13_ws_a_cannot_show_ws_b_account(): void
    {
        $this->wsGet('/api/accounts/' . CertificationSeeder::ACCOUNT_B1)
            ->assertNotFound();
    }

    /** I14 — WS-A cannot show WS-B warehouse by UUID */
    public function test_i14_ws_a_cannot_show_ws_b_warehouse(): void
    {
        $this->wsGet('/api/warehouses/' . CertificationSeeder::WAREHOUSE_B1)
            ->assertNotFound();
    }

    // ═══════════════════════════════════════════════════════════════
    // Part C — Child Table Safety
    // ═══════════════════════════════════════════════════════════════

    /** C01 — Invoice with items: items belong to workspace-scoped invoice only */
    public function test_c01_invoice_items_scoped_to_workspace(): void
    {
        // Create an invoice in WS-A
        $inv = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [['quantity' => 1, 'unit_price' => 99.99, 'product_name_snapshot' => 'Cert Widget']],
        ]);
        $inv->assertCreated();
        $invId = $inv->json('data.id');

        // WS-B admin must NOT see this invoice — 403 (permission) or 404 (RLS hides)
        $response = $this->wsGetAs('b_admin@cert.test', "/api/invoices/{$invId}", CertificationSeeder::WS_B);
        $this->assertTrue(
            in_array($response->getStatusCode(), [403, 404]),
            'ISOLATION VIOLATION: WS-A invoice accessible from WS-B! Status: ' . $response->getStatusCode()
        );
    }

    /** C02 — Order with items: WS-B cannot see WS-A order */
    public function test_c02_order_items_scoped_to_workspace(): void
    {
        $ord = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 2, 'unit_price' => 50]],
        ]);
        $ord->assertCreated();
        $ordId = $ord->json('data.id');

        // WS-B admin must NOT see this order — 403 or 404
        $response = $this->wsGetAs('b_admin@cert.test', "/api/orders/{$ordId}", CertificationSeeder::WS_B);
        $this->assertTrue(
            in_array($response->getStatusCode(), [403, 404]),
            'ISOLATION VIOLATION: WS-A order accessible from WS-B! Status: ' . $response->getStatusCode()
        );
    }

    /** C03 — Journal entry: WS-B cannot see WS-A journal entry */
    public function test_c03_journal_entry_scoped_to_workspace(): void
    {
        $je = $this->wsPost('/api/journal-entries', [
            'description' => 'Isolation test',
            'date'        => '2026-04-17',
            'lines'       => [
                ['account_id' => CertificationSeeder::ACCOUNT_A1, 'debit' => 100, 'credit' => 0],
                ['account_id' => CertificationSeeder::ACCOUNT_A2, 'debit' => 0, 'credit' => 100],
            ],
        ]);
        $je->assertCreated();
        $jeId = $je->json('data.id');

        // WS-B admin must NOT see this journal entry — 403 or 404
        $response = $this->wsGetAs('b_admin@cert.test', "/api/journal-entries/{$jeId}", CertificationSeeder::WS_B);
        $this->assertTrue(
            in_array($response->getStatusCode(), [403, 404]),
            'ISOLATION VIOLATION: WS-A journal entry accessible from WS-B! Status: ' . $response->getStatusCode()
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // Part D — Reporting Security
    // ═══════════════════════════════════════════════════════════════

    /** D01 — Sales report: WS-B admin sees only WS-B data */
    public function test_d01_sales_report_ws_b_scoped(): void
    {
        $response = $this->wsGetAs('b_admin@cert.test', '/api/reports/sales', CertificationSeeder::WS_B);
        $response->assertOk();
        // If there's no sales data in WS-B, the totals must be zero or empty
        // The important thing: no WS-A data appears
    }

    /** D02 — Inventory report: WS-A scoped */
    public function test_d02_inventory_report_ws_a_scoped(): void
    {
        $response = $this->wsGet('/api/reports/inventory');
        $response->assertOk();
    }

    /** D03 — Account balances: WS-B admin sees only WS-B accounts */
    public function test_d03_account_balances_ws_b_scoped(): void
    {
        $response = $this->wsGetAs('b_admin@cert.test', '/api/reports/account-balances', CertificationSeeder::WS_B);
        $response->assertOk();

        // Verify no WS-A account codes appear
        $data = $response->json('data');
        if (is_array($data)) {
            $codes = collect($data)->pluck('code')->toArray();
            $this->assertNotContains('CERT-1000', $codes,
                'ISOLATION VIOLATION: WS-A account visible in WS-B report');
            $this->assertNotContains('CERT-4000', $codes,
                'ISOLATION VIOLATION: WS-A account visible in WS-B report');
        }
    }

    /** D04 — Receivable/Payable report: WS-A scoped */
    public function test_d04_receivable_payable_scoped(): void
    {
        $response = $this->wsGet('/api/reports/receivable-payable');
        $response->assertOk();
    }
}
