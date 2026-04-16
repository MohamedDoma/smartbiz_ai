<?php

namespace App\Services;

use App\Models\Account;
use Illuminate\Database\Eloquent\Collection;

class AccountService
{
    /**
     * List root accounts with children (tree view).
     */
    public function list(string $workspaceId): Collection
    {
        return Account::where('workspace_id', $workspaceId)
            ->with('children')
            ->whereNull('parent_id')
            ->orderBy('code')
            ->get();
    }

    /**
     * Flat list of all accounts (for dropdowns).
     */
    public function all(string $workspaceId): Collection
    {
        return Account::where('workspace_id', $workspaceId)
            ->orderBy('code')
            ->get();
    }

    public function find(string $workspaceId, string $id): ?Account
    {
        return Account::where('workspace_id', $workspaceId)
            ->with('children')
            ->where('id', $id)
            ->first();
    }

    public function create(string $workspaceId, array $data): Account
    {
        return Account::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]));
    }

    public function update(Account $account, array $data): Account
    {
        // Accounts table has no updated_at, so we need manual save
        $account->fill($data);
        $account->save();
        return $account->fresh();
    }

    public function delete(Account $account): void
    {
        $account->delete();
    }
}
