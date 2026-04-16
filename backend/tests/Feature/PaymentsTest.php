<?php

namespace Tests\Feature;

class PaymentsTest extends SmartBizTestCase
{
    private function createInvoice(): string
    {
        $response = $this->wsPost('/api/invoices', [
            'invoice_type' => 'sale',
            'items' => [
                ['quantity' => 1, 'unit_price' => 500, 'product_name_snapshot' => 'Service'],
            ],
        ]);
        return $response->json('data.id');
    }

    public function test_create_payment(): void
    {
        $invoiceId = $this->createInvoice();

        $response = $this->wsPost('/api/payments', [
            'invoice_id'     => $invoiceId,
            'amount'         => 500,
            'payment_method' => 'bank_transfer',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.amount', '500.00')
            ->assertJsonPath('data.payment_method', 'bank_transfer')
            ->assertJsonPath('data.status', 'completed');
    }

    public function test_list_payments(): void
    {
        $response = $this->wsGet('/api/payments');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_show_payment(): void
    {
        $invoiceId = $this->createInvoice();
        $c = $this->wsPost('/api/payments', [
            'invoice_id' => $invoiceId,
            'amount' => 100,
            'payment_method' => 'cash',
        ]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/payments/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_payment_syncs_invoice_to_paid(): void
    {
        $invoiceId = $this->createInvoice();

        // Invoice total is 500 (1 × 500)
        $this->wsPost('/api/payments', [
            'invoice_id' => $invoiceId,
            'amount' => 500,
            'payment_method' => 'cash',
        ]);

        $invoice = $this->wsGet("/api/invoices/{$invoiceId}");
        $invoice->assertJsonPath('data.payment_status', 'paid');
    }

    public function test_partial_payment_syncs_to_partial(): void
    {
        $invoiceId = $this->createInvoice();

        $this->wsPost('/api/payments', [
            'invoice_id' => $invoiceId,
            'amount' => 200,
            'payment_method' => 'cash',
        ]);

        $invoice = $this->wsGet("/api/invoices/{$invoiceId}");
        $invoice->assertJsonPath('data.payment_status', 'partial');
    }

    public function test_reverse_payment_changes_status(): void
    {
        $invoiceId = $this->createInvoice();

        $payment = $this->wsPost('/api/payments', [
            'invoice_id' => $invoiceId,
            'amount' => 500,
            'payment_method' => 'cash',
        ]);
        $paymentId = $payment->json('data.id');

        // Reverse it
        $reversal = $this->wsPost("/api/payments/{$paymentId}/reverse", [
            'reason' => 'Customer refund request',
        ]);

        $reversal->assertCreated()
            ->assertJsonPath('data.is_reversal', true)
            ->assertJsonPath('data.status', 'completed');

        // Check original is now reversed
        $original = $this->wsGet("/api/payments/{$paymentId}");
        $original->assertJsonPath('data.status', 'reversed');

        // Invoice should be back to unpaid
        $invoice = $this->wsGet("/api/invoices/{$invoiceId}");
        $invoice->assertJsonPath('data.payment_status', 'unpaid');
    }

    public function test_cannot_reverse_already_reversed(): void
    {
        $invoiceId = $this->createInvoice();
        $p = $this->wsPost('/api/payments', [
            'invoice_id' => $invoiceId,
            'amount' => 100,
            'payment_method' => 'cash',
        ]);
        $pid = $p->json('data.id');

        $this->wsPost("/api/payments/{$pid}/reverse", ['reason' => 'Mistake']);
        $response = $this->wsPost("/api/payments/{$pid}/reverse", ['reason' => 'Again']);
        $response->assertUnprocessable();
    }
}
