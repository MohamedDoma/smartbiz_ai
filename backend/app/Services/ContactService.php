<?php

namespace App\Services;

use App\Models\Contact;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

/**
 * Contacts business logic — workspace-scoped queries.
 *
 * All queries go through Eloquent which respects PostgreSQL RLS
 * (since SET app.workspace_id is already set by middleware).
 * Extra workspace_id scoping is applied defensively.
 */
class ContactService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = Contact::where('workspace_id', $workspaceId);

        if (! empty($filters['type'])) {
            $query->where('type', $filters['type']);
        }

        if (! empty($filters['search'])) {
            $search = $filters['search'];
            $query->where(function ($q) use ($search) {
                $q->where('name', 'ilike', "%{$search}%")
                  ->orWhere('email', 'ilike', "%{$search}%")
                  ->orWhere('phone', 'ilike', "%{$search}%");
            });
        }

        return $query->orderBy('name')->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $contactId): ?Contact
    {
        return Contact::where('workspace_id', $workspaceId)
            ->where('id', $contactId)
            ->first();
    }

    public function create(string $workspaceId, array $data): Contact
    {
        return Contact::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]));
    }

    public function update(Contact $contact, array $data): Contact
    {
        $contact->update($data);
        return $contact->fresh();
    }

    public function delete(Contact $contact): void
    {
        $contact->delete();
    }
}
