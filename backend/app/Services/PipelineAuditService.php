<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Support\Facades\Auth;

/**
 * Centralized audit logging for Pipeline mutations.
 *
 * Uses the existing AuditLog model with workspace_id, user_id, action,
 * entity_type, entity_id, old_values, new_values.
 */
class PipelineAuditService
{
    /**
     * Log a pipeline mutation.
     *
     * @param string      $wsId       Workspace ID
     * @param string      $action     e.g. 'created', 'updated', 'deleted', 'moved', 'assigned'
     * @param string      $entityType e.g. 'pipeline', 'pipeline_stage', 'pipeline_record', 'record_document', 'custom_field'
     * @param string      $entityId   UUID of the entity
     * @param array|null  $oldValues  Before-state (for update/delete)
     * @param array|null  $newValues  After-state (for create/update)
     */
    public static function log(
        string $wsId,
        string $action,
        string $entityType,
        string $entityId,
        ?array $oldValues = null,
        ?array $newValues = null,
    ): void {
        AuditLog::create([
            'workspace_id' => $wsId,
            'user_id'      => Auth::id(),
            'action'       => $action,
            'entity_type'  => $entityType,
            'entity_id'    => $entityId,
            'old_values'   => $oldValues,
            'new_values'   => $newValues,
        ]);
    }

    /**
     * Compute meaningful diff between old and new attribute arrays.
     * Filters out unchanged values and timestamps.
     */
    public static function diff(array $old, array $new): array
    {
        $exclude = ['created_at', 'updated_at'];
        $changes = [];
        foreach ($new as $key => $val) {
            if (in_array($key, $exclude, true)) continue;
            if (!array_key_exists($key, $old) || $old[$key] !== $val) {
                $changes[$key] = ['from' => $old[$key] ?? null, 'to' => $val];
            }
        }
        return $changes;
    }
}
