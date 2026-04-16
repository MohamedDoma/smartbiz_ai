<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;

/**
 * Batch 4, Parts A+D — Load / Throughput + Stress Edge Cases.
 *
 * Part A: Rapid-fire endpoint throughput tests (measures timing).
 * Part D: Large payloads, high pagination, repeated calls.
 */
class StressTest extends SmartBizTestCase
{
    // ═══════════════════════════════════════════════════════════════
    // Part A — Load / Throughput (in-process rapid fire)
    // ═══════════════════════════════════════════════════════════════

    /** L01 — Login throughput: 20 rapid logins */
    public function test_l01_login_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 20; $i++) {
            $r = $this->postJson('/api/auth/login', [
                'email'    => FoundationSeeder::USER_EMAIL,
                'password' => FoundationSeeder::USER_PASSWORD,
            ]);
            if ($r->getStatusCode() === 200) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 20) * 1000; // ms per request

        // Assertion: all succeed and avg < 500ms/request
        $this->assertEquals(20, $ok, "Not all logins succeeded: {$ok}/20");
        $this->assertLessThan(500, $avg,
            "Login avg too slow: {$avg}ms (target <500ms)");
    }

    /** L02 — Contacts listing throughput: 30 rapid calls */
    public function test_l02_contacts_listing_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 30; $i++) {
            $r = $this->wsGet('/api/contacts');
            if ($r->getStatusCode() === 200) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 30) * 1000;

        $this->assertEquals(30, $ok, "Not all contact list calls succeeded: {$ok}/30");
        $this->assertLessThan(300, $avg,
            "Contacts list avg too slow: {$avg}ms (target <300ms)");
    }

    /** L03 — Products listing throughput: 30 rapid calls */
    public function test_l03_products_listing_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 30; $i++) {
            $r = $this->wsGet('/api/products');
            if ($r->getStatusCode() === 200) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 30) * 1000;

        $this->assertEquals(30, $ok, "Not all product list calls succeeded: {$ok}/30");
        $this->assertLessThan(300, $avg,
            "Products list avg too slow: {$avg}ms (target <300ms)");
    }

    /** L04 — Invoice creation throughput: 10 rapid creates */
    public function test_l04_invoice_creation_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 10; $i++) {
            $r = $this->wsPost('/api/invoices', [
                'invoice_type' => 'sale',
                'items' => [['quantity' => 1, 'unit_price' => 50 + $i]],
            ]);
            if ($r->getStatusCode() === 201) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 10) * 1000;

        $this->assertEquals(10, $ok, "Not all invoice creates succeeded: {$ok}/10");
        $this->assertLessThan(500, $avg,
            "Invoice create avg too slow: {$avg}ms (target <500ms)");
    }

    /** L05 — Reports throughput: 20 rapid calls to sales report */
    public function test_l05_reports_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 20; $i++) {
            $r = $this->wsGet('/api/reports/sales');
            if ($r->getStatusCode() === 200) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 20) * 1000;

        $this->assertEquals(20, $ok, "Not all report calls succeeded: {$ok}/20");
        $this->assertLessThan(300, $avg,
            "Reports avg too slow: {$avg}ms (target <300ms)");
    }

    /** L06 — Auth/me throughput: 30 rapid calls */
    public function test_l06_auth_me_throughput(): void
    {
        $start = microtime(true);
        $ok = 0;

        for ($i = 0; $i < 30; $i++) {
            $r = $this->authGet('/api/auth/me');
            if ($r->getStatusCode() === 200) $ok++;
        }

        $elapsed = microtime(true) - $start;
        $avg = ($elapsed / 30) * 1000;

        $this->assertEquals(30, $ok, "Not all auth/me calls succeeded: {$ok}/30");
        $this->assertLessThan(200, $avg,
            "Auth/me avg too slow: {$avg}ms (target <200ms)");
    }

    // ═══════════════════════════════════════════════════════════════
    // Part D — Stress Edge Cases
    // ═══════════════════════════════════════════════════════════════

    /** E01 — Large payload: invoice with 50 items */
    public function test_e01_large_payload_many_invoice_items(): void
    {
        $items = [];
        for ($i = 0; $i < 50; $i++) {
            $items[] = [
                'quantity'              => 1 + $i,
                'unit_price'            => 10.00,
                'product_name_snapshot' => "Stress Item #{$i}",
            ];
        }

        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items'        => $items,
        ]);
        $response->assertCreated();
        $this->assertCount(50, $response->json('data.items'),
            'Invoice should have exactly 50 items');

        // Verify total = sum of (qty * price)
        $expectedTotal = 0;
        for ($i = 0; $i < 50; $i++) {
            $expectedTotal += (1 + $i) * 10;
        }
        $this->assertEquals(
            number_format($expectedTotal, 2, '.', ''),
            $response->json('data.total_amount'),
            'Total must equal sum of item totals'
        );
    }

    /** E02 — High pagination: request page 100+ */
    public function test_e02_high_pagination(): void
    {
        $response = $this->wsGet('/api/contacts?page=100&per_page=10');
        $response->assertOk();
        // Data should be empty (no 100th page), but request should not crash
        $this->assertIsArray($response->json('data'));
    }

    /** E03 — Rapid repeated identical GET requests (idempotency) */
    public function test_e03_rapid_repeated_identical_get(): void
    {
        $results = [];
        for ($i = 0; $i < 20; $i++) {
            $r = $this->wsGet('/api/contacts');
            $results[] = $r->getStatusCode();
        }

        // All must return 200
        $this->assertEquals(
            array_fill(0, 20, 200),
            $results,
            'All identical GET requests must return 200'
        );
    }

    /** E04 — Repeated same POST create (non-idempotent = multiple records) */
    public function test_e04_repeated_same_post_creates_multiple(): void
    {
        $ids = [];
        for ($i = 0; $i < 5; $i++) {
            $r = $this->wsPost('/api/contacts', [
                'type' => 'customer',
                'name' => 'Stress Repeat Customer',
            ]);
            $r->assertCreated();
            $ids[] = $r->json('data.id');
        }

        // All IDs should be unique (each POST creates a new record)
        $this->assertCount(5, array_unique($ids),
            'Each POST should create a separate record with unique ID');
    }
}
