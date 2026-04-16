<?php

namespace App\Services;

use App\Models\RecurringExpense;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class RecurringExpenseService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = RecurringExpense::where('workspace_id', $workspaceId);

        if (isset($filters['is_active'])) {
            $query->where('is_active', filter_var($filters['is_active'], FILTER_VALIDATE_BOOLEAN));
        }

        return $query->orderBy('next_due_date')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?RecurringExpense
    {
        return RecurringExpense::where('workspace_id', $workspaceId)->find($id);
    }

    public function create(string $workspaceId, array $data): RecurringExpense
    {
        return RecurringExpense::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]))->fresh();
    }

    public function update(RecurringExpense $expense, array $data): RecurringExpense
    {
        $expense->update($data);
        return $expense->fresh();
    }

    public function delete(RecurringExpense $expense): void
    {
        $expense->delete();
    }
}
