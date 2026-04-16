<?php

namespace Tests\Feature;

class RecurringExpensesTest extends SmartBizTestCase
{
    public function test_create_recurring_expense(): void
    {
        $response = $this->wsPost('/api/recurring-expenses', [
            'category'      => 'Office Rent',
            'amount'        => 5000,
            'frequency'     => 'monthly',
            'next_due_date' => '2026-05-01',
        ]);
        $response->assertCreated()
            ->assertJsonPath('data.category', 'Office Rent')
            ->assertJsonPath('data.frequency', 'monthly')
            ->assertJsonPath('data.is_active', true);
    }

    public function test_list_recurring_expenses(): void
    {
        $response = $this->wsGet('/api/recurring-expenses');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_show_recurring_expense(): void
    {
        $c = $this->wsPost('/api/recurring-expenses', [
            'category' => 'Internet',
            'amount' => 200,
            'frequency' => 'monthly',
            'next_due_date' => '2026-06-01',
        ]);
        $id = $c->json('data.id');
        $response = $this->wsGet("/api/recurring-expenses/{$id}");
        $response->assertOk()->assertJsonPath('data.id', $id);
    }

    public function test_update_recurring_expense(): void
    {
        $c = $this->wsPost('/api/recurring-expenses', [
            'category' => 'Before',
            'amount' => 100,
            'frequency' => 'weekly',
            'next_due_date' => '2026-05-01',
        ]);
        $id = $c->json('data.id');
        $response = $this->wsPut("/api/recurring-expenses/{$id}", [
            'amount' => 200,
            'is_active' => false,
        ]);
        $response->assertOk()
            ->assertJsonPath('data.amount', '200.00')
            ->assertJsonPath('data.is_active', false);
    }

    public function test_delete_recurring_expense(): void
    {
        $c = $this->wsPost('/api/recurring-expenses', [
            'category' => 'Temp',
            'amount' => 50,
            'frequency' => 'daily',
            'next_due_date' => '2026-05-01',
        ]);
        $id = $c->json('data.id');
        $this->wsDelete("/api/recurring-expenses/{$id}")->assertOk();
        $this->wsGet("/api/recurring-expenses/{$id}")->assertNotFound();
    }
}
