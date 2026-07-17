<?php
namespace App\Models;

use App\Exceptions\ProvisioningException;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProvisioningRun extends Model
{
    use HasUuids;

    protected $table = 'provisioning_runs';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    /**
     * Status vocabulary:
     *   preview              — dry-run plan generation
     *   prepared             — ready for entity provisioning (snapshot captured)
     *   processing           — entity creation in progress
     *   foundation_applied   — core entities provisioned (1.6B), operational pending (1.6C)
     *   applied              — fully provisioned, awaiting finalization (1.6D)
     *   onboarding_complete  — finalized: owner role assigned, onboarding marked done (terminal success)
     *   rolled_back          — reverted to previous config
     *   failed               — error during provisioning
     */
    public const STATUS_PREVIEW              = 'preview';
    public const STATUS_PREPARED             = 'prepared';
    public const STATUS_PROCESSING           = 'processing';
    public const STATUS_FOUNDATION_APPLIED   = 'foundation_applied';
    public const STATUS_APPLIED              = 'applied';
    public const STATUS_ONBOARDING_COMPLETE  = 'onboarding_complete';
    public const STATUS_ROLLED_BACK          = 'rolled_back';
    public const STATUS_FAILED               = 'failed';

    /**
     * Allowed state transitions.
     * Key = current status, value = array of valid next statuses.
     */
    private const TRANSITIONS = [
        self::STATUS_PREVIEW              => [self::STATUS_PREPARED, self::STATUS_ROLLED_BACK],
        self::STATUS_PREPARED             => [self::STATUS_PROCESSING, self::STATUS_ROLLED_BACK, self::STATUS_FAILED],
        self::STATUS_PROCESSING           => [self::STATUS_FOUNDATION_APPLIED, self::STATUS_FAILED],
        self::STATUS_FOUNDATION_APPLIED   => [self::STATUS_APPLIED, self::STATUS_ROLLED_BACK],
        self::STATUS_APPLIED              => [self::STATUS_ONBOARDING_COMPLETE, self::STATUS_ROLLED_BACK],
        self::STATUS_ONBOARDING_COMPLETE  => [self::STATUS_ROLLED_BACK],
        self::STATUS_ROLLED_BACK          => [],
        self::STATUS_FAILED               => [self::STATUS_ROLLED_BACK, self::STATUS_PREPARED],
    ];

    protected $fillable = [
        'workspace_id', 'blueprint_id', 'status', 'config',
        'applied_by', 'applied_at', 'version',
        'rollback_config', 'error_message', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'config'          => 'array',
            'rollback_config' => 'array',
            'applied_at'      => 'datetime',
            'created_at'      => 'datetime',
        ];
    }

    /**
     * Transition to a new status with validation.
     *
     * @throws ProvisioningException if the transition is invalid
     */
    public function transitionTo(string $newStatus, array $extraAttributes = []): void
    {
        $allowed = self::TRANSITIONS[$this->status] ?? [];

        if (!in_array($newStatus, $allowed, true)) {
            throw new ProvisioningException(
                "Invalid status transition: '{$this->status}' → '{$newStatus}'. " .
                "Allowed: [" . implode(', ', $allowed) . "].",
                'invalid_status_transition',
                409,
            );
        }

        $this->update(array_merge($extraAttributes, ['status' => $newStatus]));
    }

    /**
     * Check if a transition is allowed without performing it.
     */
    public function canTransitionTo(string $newStatus): bool
    {
        return in_array($newStatus, self::TRANSITIONS[$this->status] ?? [], true);
    }

    // ── Relationships ──

    public function workspace(): BelongsTo { return $this->belongsTo(Workspace::class); }
    public function blueprint(): BelongsTo { return $this->belongsTo(DiscoveryBlueprint::class, 'blueprint_id'); }
    public function appliedBy(): BelongsTo { return $this->belongsTo(User::class, 'applied_by'); }
}
