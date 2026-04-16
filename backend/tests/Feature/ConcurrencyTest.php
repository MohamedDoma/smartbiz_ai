<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;

/**
 * Batch 4, Parts B+C — Concurrency + Consistency Tests (P01–P05, C01–C03).
 *
 * Tests race conditions on payments, inventory, reservations, orders, and journals.
 * After concurrent operations, verifies data consistency.
 *
 * NOTE: PHPUnit runs in-process, so we simulate concurrency by running
 * sequential rapid-fire operations that stress the same resources.
 * True multi-process concurrency is tested via the load script.
 */
class ConcurrencyTest extends SmartBizTestCase
{
    // ═══════════════════════════════════════════════════════════════
    // P01 — Multiple payments on same invoice (no double counting)
    // ═══════════════════════════════════════════════════════════════

    public function test_p01_concurrent_payments_same_invoice(): void
    {
        // Create an invoice worth 100
        $inv = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items'        => [['quantity' => 2, 'unit_price' => 50]],
        ]);
        $inv->assertCreated();
        $invId = $inv->json('data.id');
        $total = (float) $inv->json('data.total_amount');
        $this->assertEquals(100.0, $total);

        // Simulate 5 rapid sequential payments of 30 each = 150 > 100
        $paymentIds = [];
        for ($i = 0; $i < 5; $i++) {
            $p = $this->wsPost('/api/payments', [
                'invoice_id'     => $invId,
                'amount'         => 30,
                'payment_method' => 'cash',
            ]);
            // All created — the system accepts overpayment (common ERP behavior)
            $this->assertContains($p->getStatusCode(), [200, 201],
                "Payment {$i} failed with status: " . $p->getStatusCode());
            $paymentIds[] = $p->json('data.id');
        }

        // C01 — Verify invoice payment_status is correct
        $finalInv = $this->wsGet("/api/invoices/{$invId}");
        $finalInv->assertOk();
        $this->assertEquals('paid', $finalInv->json('data.payment_status'),
            'Invoice should be marked paid when total payments >= invoice amount');

        // Verify the total payment amount in DB is correct
        $totalPaid = DB::table('payments')
            ->where('invoice_id', $invId)
            ->where('status', 'completed')
            ->where('is_reversal', false)
            ->sum('amount');
        $this->assertEquals(150.0, (float) $totalPaid,
            'Total paid amount must equal sum of all payments (150)');
    }

    // ═══════════════════════════════════════════════════════════════
    // P02 — Concurrent stock movements (no negative stock)
    // ═══════════════════════════════════════════════════════════════

    public function test_p02_concurrent_stock_movements(): void
    {
        // Create a fresh isolated product so we start from 0 stock
        $prod = $this->wsPost('/api/products', [
            'name' => 'StockRace-' . uniqid(),
            'sku'  => 'SR-' . uniqid(),
            'base_price' => 10,
        ]);
        $prod->assertCreated();
        $productId = $prod->json('data.id');

        // Stock in: exactly 100 units
        $this->wsPost('/api/inventory-movements', [
            'warehouse_id'    => CertificationSeeder::WAREHOUSE_A1,
            'product_id'      => $productId,
            'movement_type'   => 'purchase_receipt',
            'quantity_change'  => 100,
        ])->assertCreated();

        // Now attempt 12 rapid outflows of 10 each = 120 (> 100 available)
        $successes = 0;
        $failures  = 0;
        for ($i = 0; $i < 12; $i++) {
            $r = $this->wsPost('/api/inventory-movements', [
                'warehouse_id'    => CertificationSeeder::WAREHOUSE_A1,
                'product_id'      => $productId,
                'movement_type'   => 'sale_shipment',
                'quantity_change'  => 10,
            ]);
            if ($r->getStatusCode() === 201) {
                $successes++;
            } else {
                $failures++;
            }
        }

        // At most 10 should succeed (10*10=100), at least 2 should fail
        $this->assertLessThanOrEqual(10, $successes,
            "More than 10 outflows of 10 succeeded — possible negative stock! ({$successes} successes)");
        $this->assertGreaterThanOrEqual(2, $failures,
            'Expected at least 2 failures to prevent negative stock');

        // C02 — Verify final stock level is >= 0
        $levels = $this->wsGet('/api/inventory-movements/levels?' . http_build_query([
            'warehouse_id' => CertificationSeeder::WAREHOUSE_A1,
            'product_id'   => $productId,
        ]));
        $levels->assertOk();
        $data = $levels->json('data');
        if (is_array($data) && count($data) > 0) {
            $currentStock = (float) $data[0]['current_stock'];
            $this->assertGreaterThanOrEqual(0, $currentStock,
                "CRITICAL: Negative stock detected! Current level: {$currentStock}");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // P03 — Concurrent reservation attempts
    // ═══════════════════════════════════════════════════════════════

    public function test_p03_concurrent_reservation_attempts(): void
    {
        // Create an order with an item so we have an order_item_id
        $ord = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 50, 'unit_price' => 10]],
        ]);
        $ord->assertCreated();
        $ordId = $ord->json('data.id');
        $orderItemId = $ord->json('data.items.0.id');

        // Attempt rapid reservations — all should succeed as separate records
        $created = 0;
        for ($i = 0; $i < 5; $i++) {
            $r = $this->wsPost('/api/stock-reservations', [
                'order_id'          => $ordId,
                'order_item_id'     => $orderItemId,
                'product_id'        => CertificationSeeder::PRODUCT_A1,
                'warehouse_id'      => CertificationSeeder::WAREHOUSE_A1,
                'reserved_quantity' => 10,
            ]);
            if ($r->getStatusCode() === 201) $created++;
        }

        $this->assertGreaterThan(0, $created,
            'At least one reservation should be created');

        // C03 — Verify each reservation has consistent quantities
        $list = $this->wsGet('/api/stock-reservations?order_id=' . $ordId);
        $list->assertOk();
        foreach ($list->json('data') as $res) {
            $this->assertEquals(10, (float) $res['reserved_quantity']);
            $this->assertEquals('active', $res['status']);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // P04 — Concurrent order status updates
    // ═══════════════════════════════════════════════════════════════

    public function test_p04_concurrent_order_status_updates(): void
    {
        $ord = $this->wsPost('/api/orders', [
            'order_type' => 'sale_order',
            'items' => [['quantity' => 1, 'unit_price' => 100]],
        ]);
        $ord->assertCreated();
        $ordId = $ord->json('data.id');

        // Rapid status transitions: draft → confirmed → processing → completed
        $transitions = ['confirmed', 'processing', 'completed'];
        foreach ($transitions as $status) {
            $r = $this->wsPut("/api/orders/{$ordId}", ['status' => $status]);
            $r->assertOk();
            $this->assertEquals($status, $r->json('data.status'));
        }

        // Final state must be 'completed'
        $final = $this->wsGet("/api/orders/{$ordId}");
        $final->assertOk();
        $this->assertEquals('completed', $final->json('data.status'));
    }

    // ═══════════════════════════════════════════════════════════════
    // P05 — Concurrent journal writes (all must be balanced)
    // ═══════════════════════════════════════════════════════════════

    public function test_p05_concurrent_journal_writes(): void
    {
        $entryIds = [];
        for ($i = 0; $i < 10; $i++) {
            $amount = 100 + $i;
            $je = $this->wsPost('/api/journal-entries', [
                'description' => "Concurrency test JE #{$i}",
                'date'        => '2026-04-17',
                'lines'       => [
                    ['account_id' => CertificationSeeder::ACCOUNT_A1, 'debit' => $amount, 'credit' => 0],
                    ['account_id' => CertificationSeeder::ACCOUNT_A2, 'debit' => 0, 'credit' => $amount],
                ],
            ]);
            $je->assertCreated();
            $entryIds[] = $je->json('data.id');
        }

        // Verify each entry is balanced
        foreach ($entryIds as $jeId) {
            $entry = $this->wsGet("/api/journal-entries/{$jeId}");
            $entry->assertOk();
            $lines = $entry->json('data.lines');
            $totalDebit  = array_sum(array_column($lines, 'debit'));
            $totalCredit = array_sum(array_column($lines, 'credit'));
            $this->assertEquals($totalDebit, $totalCredit,
                "Journal entry {$jeId} is UNBALANCED: debit={$totalDebit}, credit={$totalCredit}");
        }
    }
}
