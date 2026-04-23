<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Three-layer AI memory system.
 *
 * Layers:
 * 1. session_context — current workflow state, recent entities, last actions (TTL: 1h)
 * 2. entity_frequency — auto-tracked most-used contacts/products/warehouses
 * 3. business_memory — recurring patterns, preferences (permanent)
 */
class AiMemoryService
{
    /**
     * Store session context (auto-expires in 1 hour).
     */
    public function setSessionContext(string $workspaceId, string $userId, string $key, mixed $value): void
    {
        DB::table('ai_memory')->updateOrInsert(
            [
                'workspace_id' => $workspaceId,
                'user_id'      => $userId,
                'memory_type'  => 'session_context',
                'key'          => $key,
            ],
            [
                'value'      => json_encode($value),
                'score'      => 0,
                'expires_at' => now()->addHour(),
                'updated_at' => now(),
            ],
        );
    }

    /**
     * Get session context by key.
     */
    public function getSessionContext(string $workspaceId, string $userId, string $key): mixed
    {
        $row = DB::table('ai_memory')
            ->where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->where('memory_type', 'session_context')
            ->where('key', $key)
            ->where(function ($q) {
                $q->whereNull('expires_at')->orWhere('expires_at', '>', now());
            })
            ->first();

        return $row ? json_decode($row->value, true) : null;
    }

    /**
     * Record an entity access — increments frequency score.
     */
    public function recordEntityAccess(string $workspaceId, string $entityType, string $entityId, ?string $entityName = null): void
    {
        $key = "{$entityType}:{$entityId}";

        $existing = DB::table('ai_memory')
            ->where('workspace_id', $workspaceId)
            ->whereNull('user_id')
            ->where('memory_type', 'entity_frequency')
            ->where('key', $key)
            ->first();

        if ($existing) {
            DB::table('ai_memory')->where('id', $existing->id)->update([
                'score'      => DB::raw('score + 1'),
                'value'      => json_encode([
                    'entity_type' => $entityType,
                    'entity_id'   => $entityId,
                    'entity_name' => $entityName,
                    'last_access' => now()->toISOString(),
                ]),
                'updated_at' => now(),
            ]);
        } else {
            DB::table('ai_memory')->insert([
                'id'           => Str::uuid()->toString(),
                'workspace_id' => $workspaceId,
                'user_id'      => null,
                'memory_type'  => 'entity_frequency',
                'key'          => $key,
                'value'        => json_encode([
                    'entity_type' => $entityType,
                    'entity_id'   => $entityId,
                    'entity_name' => $entityName,
                    'last_access' => now()->toISOString(),
                ]),
                'score'        => 1,
                'created_at'   => now(),
                'updated_at'   => now(),
            ]);
        }
    }

    /**
     * Get most frequently used entities of a type.
     */
    public function getFrequentEntities(string $workspaceId, string $entityType, int $limit = 5): array
    {
        return DB::table('ai_memory')
            ->where('workspace_id', $workspaceId)
            ->where('memory_type', 'entity_frequency')
            ->where('key', 'LIKE', "{$entityType}:%")
            ->orderByDesc('score')
            ->limit($limit)
            ->get()
            ->map(fn ($row) => array_merge(json_decode($row->value, true), ['score' => $row->score]))
            ->toArray();
    }

    /**
     * Store permanent business memory.
     */
    public function setBusinessMemory(string $workspaceId, string $key, mixed $value): void
    {
        DB::table('ai_memory')->updateOrInsert(
            [
                'workspace_id' => $workspaceId,
                'user_id'      => null,
                'memory_type'  => 'business_memory',
                'key'          => $key,
            ],
            [
                'value'      => json_encode($value),
                'score'      => 0,
                'updated_at' => now(),
            ],
        );
    }

    /**
     * Get business memory by key.
     */
    public function getBusinessMemory(string $workspaceId, string $key): mixed
    {
        $row = DB::table('ai_memory')
            ->where('workspace_id', $workspaceId)
            ->whereNull('user_id')
            ->where('memory_type', 'business_memory')
            ->where('key', $key)
            ->first();

        return $row ? json_decode($row->value, true) : null;
    }

    /**
     * Build context block for prompt injection.
     */
    public function getRelevantMemory(string $workspaceId, string $userId): array
    {
        $context = [];

        // Session context (non-expired)
        $session = DB::table('ai_memory')
            ->where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->where('memory_type', 'session_context')
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()))
            ->orderByDesc('updated_at')
            ->limit(10)
            ->get();

        if ($session->isNotEmpty()) {
            $context['session'] = $session->mapWithKeys(fn ($r) => [$r->key => json_decode($r->value, true)])->toArray();
        }

        // Top frequent entities
        foreach (['contact', 'product'] as $type) {
            $frequent = $this->getFrequentEntities($workspaceId, $type, 3);
            if (! empty($frequent)) {
                $context["frequent_{$type}s"] = array_map(fn ($e) => $e['entity_name'] ?? $e['entity_id'], $frequent);
            }
        }

        return $context;
    }

    /**
     * Clean expired session contexts.
     */
    public function cleanExpired(): int
    {
        return DB::table('ai_memory')
            ->where('memory_type', 'session_context')
            ->whereNotNull('expires_at')
            ->where('expires_at', '<', now())
            ->delete();
    }
}
