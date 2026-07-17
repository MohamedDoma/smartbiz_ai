<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Maps Blueprint local keys → actual database entity IDs.
 *
 * Provides stable, workspace-scoped identity for provisioned entities
 * so that re-running or updating a Blueprint can update (not duplicate) entities.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $entity_type       location|department|team|role|warehouse|...
 * @property string $local_key         Blueprint local key (e.g. "sales_dept")
 * @property string $entity_id         Actual database UUID of created entity
 * @property string $ownership_type    created_by_provisioning|adopted_template_entity|created_by_template
 * @property string|null $last_provisioning_run_id
 * @property string|null $last_blueprint_id
 * @property int    $last_blueprint_version
 * @property array|null $metadata
 */
class ProvisioningEntityBinding extends Model
{
    use HasUuids;

    protected $table = 'provisioning_entity_bindings';
    protected $keyType = 'string';
    public $incrementing = false;

    /** Ownership type constants */
    public const OWNERSHIP_CREATED_BY_PROVISIONING = 'created_by_provisioning';
    public const OWNERSHIP_ADOPTED_TEMPLATE_ENTITY = 'adopted_template_entity';
    public const OWNERSHIP_CREATED_BY_TEMPLATE     = 'created_by_template';

    protected $fillable = [
        'workspace_id',
        'entity_type',
        'local_key',
        'entity_id',
        'ownership_type',
        'last_provisioning_run_id',
        'last_blueprint_id',
        'last_blueprint_version',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'last_blueprint_version' => 'integer',
            'metadata'               => 'array',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }

    public function provisioningRun(): BelongsTo
    {
        return $this->belongsTo(ProvisioningRun::class, 'last_provisioning_run_id');
    }

    /**
     * Check if exact entity-level template provenance exists for a given workspace entity.
     *
     * This is the authoritative check for whether an entity was created by a template
     * and can be safely adopted by Blueprint provisioning.
     */
    public static function hasTemplateProvenance(
        string $workspaceId,
        string $entityType,
        string $entityId,
    ): bool {
        return static::where('workspace_id', $workspaceId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->whereIn('ownership_type', [
                self::OWNERSHIP_CREATED_BY_TEMPLATE,
                self::OWNERSHIP_CREATED_BY_PROVISIONING,
                self::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY,
            ])
            ->exists();
    }

    /**
     * Find a binding by workspace, entity type, and entity ID.
     */
    public static function findByEntity(
        string $workspaceId,
        string $entityType,
        string $entityId,
    ): ?self {
        return static::where('workspace_id', $workspaceId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->first();
    }
}
