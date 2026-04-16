<?php

namespace Tests\Feature;

class ReportingTest extends SmartBizTestCase
{
    public function test_sales_summary(): void
    {
        $response = $this->wsGet('/api/reports/sales');
        $response->assertOk()
            ->assertJsonStructure(['data' => [
                'total_invoices', 'total_sales', 'collected', 'outstanding',
                'total_orders', 'total_order_value',
            ]]);
    }

    public function test_invoice_payment_summary(): void
    {
        $response = $this->wsGet('/api/reports/invoices-payments');
        $response->assertOk()->assertJsonStructure(['data']);
    }

    public function test_inventory_summary(): void
    {
        $response = $this->wsGet('/api/reports/inventory');
        $response->assertOk()
            ->assertJsonStructure(['data' => [
                'total_stock_entries', 'total_units', 'low_stock_count', 'low_stock_items',
            ]]);
    }

    public function test_account_balances(): void
    {
        $response = $this->wsGet('/api/reports/account-balances');
        $response->assertOk()
            ->assertJsonStructure(['data' => ['accounts', 'by_type']]);
    }

    public function test_receivable_payable(): void
    {
        $response = $this->wsGet('/api/reports/receivable-payable');
        $response->assertOk()
            ->assertJsonStructure(['data' => [
                'receivable' => ['count', 'total'],
                'payable'    => ['count', 'total'],
            ]]);
    }
}
