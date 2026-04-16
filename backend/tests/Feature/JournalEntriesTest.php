<?php

namespace Tests\Feature;

class JournalEntriesTest extends SmartBizTestCase
{
    private function createTestAccounts(): array
    {
        $debitAccount = $this->wsPost('/api/accounts', [
            'code' => 'JD' . uniqid(), 'name' => 'Debit Acc', 'type' => 'asset',
        ]);
        $creditAccount = $this->wsPost('/api/accounts', [
            'code' => 'JC' . uniqid(), 'name' => 'Credit Acc', 'type' => 'revenue',
        ]);
        return [
            'debit'  => $debitAccount->json('data.id'),
            'credit' => $creditAccount->json('data.id'),
        ];
    }

    public function test_create_balanced_journal_entry(): void
    {
        $accs = $this->createTestAccounts();

        $response = $this->wsPost('/api/journal-entries', [
            'description' => 'Test balanced entry',
            'lines' => [
                ['account_id' => $accs['debit'],  'debit' => 100, 'credit' => 0],
                ['account_id' => $accs['credit'], 'debit' => 0,   'credit' => 100],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.description', 'Test balanced entry')
            ->assertJsonPath('data.status', 'draft')
            ->assertJsonCount(2, 'data.lines');

        // Verify debit/credit amounts
        $lines = $response->json('data.lines');
        $totalDebit = array_sum(array_column($lines, 'debit'));
        $totalCredit = array_sum(array_column($lines, 'credit'));
        $this->assertEquals($totalDebit, $totalCredit, 'Entry must be balanced');
    }

    public function test_show_journal_entry_with_lines(): void
    {
        $accs = $this->createTestAccounts();
        $c = $this->wsPost('/api/journal-entries', [
            'description' => 'Show test',
            'lines' => [
                ['account_id' => $accs['debit'],  'debit' => 50, 'credit' => 0],
                ['account_id' => $accs['credit'], 'debit' => 0,  'credit' => 50],
            ],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsGet("/api/journal-entries/{$id}");
        $response->assertOk()
            ->assertJsonStructure(['data' => ['lines']])
            ->assertJsonCount(2, 'data.lines');
    }

    public function test_unbalanced_entry_returns_422(): void
    {
        $accs = $this->createTestAccounts();

        $response = $this->wsPost('/api/journal-entries', [
            'description' => 'Unbalanced',
            'lines' => [
                ['account_id' => $accs['debit'], 'debit' => 100, 'credit' => 0],
                ['account_id' => $accs['credit'], 'debit' => 0, 'credit' => 50],
            ],
        ]);

        $response->assertUnprocessable();
    }

    public function test_update_journal_entry_status(): void
    {
        $accs = $this->createTestAccounts();
        $c = $this->wsPost('/api/journal-entries', [
            'description' => 'Status test',
            'lines' => [
                ['account_id' => $accs['debit'],  'debit' => 200, 'credit' => 0],
                ['account_id' => $accs['credit'], 'debit' => 0,   'credit' => 200],
            ],
        ]);
        $id = $c->json('data.id');

        $response = $this->wsPut("/api/journal-entries/{$id}", ['status' => 'posted']);
        $response->assertOk()->assertJsonPath('data.status', 'posted');
    }

    public function test_list_journal_entries(): void
    {
        $response = $this->wsGet('/api/journal-entries');
        $response->assertOk()->assertJsonStructure(['data', 'meta']);
    }

    public function test_entry_requires_minimum_two_lines(): void
    {
        $accs = $this->createTestAccounts();

        $response = $this->wsPost('/api/journal-entries', [
            'description' => 'Single line',
            'lines' => [
                ['account_id' => $accs['debit'], 'debit' => 100, 'credit' => 0],
            ],
        ]);

        $response->assertUnprocessable();
    }
}
