<?php

namespace App\Services;

use App\Models\JournalEntry;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class JournalEntryService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = JournalEntry::where('workspace_id', $workspaceId);

        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        return $query->orderByDesc('date')
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?JournalEntry
    {
        return JournalEntry::where('workspace_id', $workspaceId)
            ->with('lines')
            ->where('id', $id)
            ->first();
    }

    /**
     * Create journal entry with lines in a single transaction.
     *
     * The DB enforces double-entry via:
     * 1. CHECK constraint: each line must be debit-only OR credit-only
     * 2. DEFERRED CONSTRAINT trigger: sum(debit) must equal sum(credit) per entry
     *
     * We also validate debit=credit in the service before sending to DB
     * to give a cleaner error message.
     */
    public function create(string $workspaceId, string $userId, array $data): JournalEntry
    {
        return DB::transaction(function () use ($workspaceId, $userId, $data) {
            $lines = $data['lines'] ?? [];
            unset($data['lines']);

            // Pre-validate debit = credit for a clear error message
            $totalDebit = 0;
            $totalCredit = 0;
            foreach ($lines as $line) {
                $totalDebit += (float) ($line['debit'] ?? 0);
                $totalCredit += (float) ($line['credit'] ?? 0);
            }

            if (abs($totalDebit - $totalCredit) > 0.001) {
                throw new \InvalidArgumentException(
                    "Journal entry is unbalanced: total debits ({$totalDebit}) must equal total credits ({$totalCredit})"
                );
            }

            $entry = JournalEntry::create(array_merge($data, [
                'workspace_id'  => $workspaceId,
                'created_by'    => $userId,
                'status'        => $data['status'] ?? 'draft',
                'currency'      => $data['currency'] ?? 'USD',
                'exchange_rate' => $data['exchange_rate'] ?? 1.0,
                'date'          => $data['date'] ?? now()->toDateString(),
            ]));

            foreach ($lines as $line) {
                $entry->lines()->create($line);
            }

            return $entry->load('lines');
        });
    }

    /**
     * Update entry-level fields only (status, description, etc).
     * Lines are immutable after creation.
     */
    public function update(JournalEntry $entry, array $data): JournalEntry
    {
        unset($data['lines']);
        $entry->fill($data);
        $entry->save();
        return $entry->fresh('lines');
    }
}
