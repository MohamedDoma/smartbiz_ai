<?php

namespace App\Services;

use App\Events\WorkspaceOnboardingCompleted;
use App\Exceptions\ProvisioningException;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\Branch;
use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use App\Models\Department;
use App\Models\DiscoveryBlueprint;
use App\Models\MembershipRole;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Models\ProvisioningEntityBinding;
use App\Models\ProvisioningRun;
use App\Models\Role;
use App\Models\Team;
use App\Models\Warehouse;
use App\Models\Workspace;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceFeatureFlag;
use App\Models\WorkspaceMembership;
use App\Services\Blueprint\BlueprintSchema;
use App\Services\Blueprint\BlueprintValidator;
use App\Services\Provisioning\CoreEntityProvisioner;
use App\Services\Provisioning\OperationalEntityProvisioner;
use App\Services\Provisioning\ProvisioningPlanBuilder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * ERP Provisioning Engine.
 *
 * Transforms validated canonical discovery Blueprints into workspace configurations.
 *
 * Lifecycle:
 *   1. preview()  — Revalidate Blueprint, build execution plan, create/update preview run
 *   2. apply()    — Revalidate, create entities, transition prepared → processing → foundation_applied
 *   3. rollback() — Revert entities + config from a foundation_applied/prepared/applied run
 */
class ProvisioningService
{
    private ProvisioningPlanBuilder $planBuilder;
    private BlueprintValidator $validator;

    public function __construct()
    {
        $this->planBuilder = new ProvisioningPlanBuilder();
        $this->validator   = new BlueprintValidator();
    }

    // ═══════════════════════════════════════════════════════════════
    //  Preview
    // ═══════════════════════════════════════════════════════════════

    /**
     * Preview: revalidate, build plan, return summary without mutating workspace.
     *
     * Idempotent: reuses or updates existing preview run for same workspace+blueprint+version.
     */
    public function preview(string $workspaceId, string $blueprintId): array
    {
        $blueprint = $this->loadAndVerifyBlueprint($workspaceId, $blueprintId);

        // Revalidate before proceeding
        $validation = $this->revalidateBlueprint($blueprint);
        if (!$validation['valid']) {
            return [
                'status'     => 'validation_failed',
                'errors'     => $validation['errors'],
                'warnings'   => $validation['warnings'],
                'can_apply'  => false,
            ];
        }

        // Build deterministic plan
        $plan = $this->planBuilder->build($blueprint, $workspaceId);

        // Build config mapping for preview
        $configMapping = $this->planBuilder->buildConfigMapping(
            $blueprint->blueprint,
            $blueprint->id,
            $blueprint->version,
        );

        // Idempotent preview run: reuse existing preview for same blueprint+version
        $existingPreview = ProvisioningRun::where('workspace_id', $workspaceId)
            ->where('blueprint_id', $blueprintId)
            ->where('status', 'preview')
            ->first();

        if ($existingPreview && ($existingPreview->config['blueprint_version'] ?? null) === $blueprint->version) {
            // Update existing preview with latest plan
            $existingPreview->update([
                'config' => array_merge($plan, ['config_mapping' => $configMapping]),
            ]);
            $run = $existingPreview;
        } else {
            // Delete stale preview and create fresh one
            if ($existingPreview) {
                $existingPreview->delete();
            }

            $run = ProvisioningRun::create([
                'workspace_id' => $workspaceId,
                'blueprint_id' => $blueprintId,
                'status'       => 'preview',
                'config'       => array_merge($plan, ['config_mapping' => $configMapping]),
                'version'      => $this->nextVersion($workspaceId),
                'created_at'   => now(),
            ]);
        }

        return [
            'run_id'       => $run->id,
            'status'       => 'preview',
            'blueprint_id' => $blueprint->id,
            'blueprint_version' => $blueprint->version,
            'plan_summary' => $plan['summary'],
            'warnings'     => $plan['warnings'],
            'validation'   => ['valid' => true, 'error_count' => 0],
            'can_apply'    => true,
            'config_mapping' => $configMapping,
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Apply — Core Entity Provisioning (Task 1.6B)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Apply: revalidate, create core entities, transition to foundation_applied.
     *
     * Task 1.6B creates: locations, departments, teams, roles, permissions, module flags, config.
     * Does NOT create: warehouses, pipelines, approvals, commissions, financial settings.
     * Does NOT mark onboarding complete or set status to 'applied'.
     */
    public function apply(string $workspaceId, string $blueprintId, string $userId): array
    {
        $blueprint = $this->loadAndVerifyBlueprint($workspaceId, $blueprintId);

        // Revalidate before proceeding
        $validation = $this->revalidateBlueprint($blueprint);
        if (!$validation['valid']) {
            return [
                'status' => 'validation_failed',
                'errors' => $validation['errors'],
                'can_apply' => false,
            ];
        }

        // ── Idempotency: return existing run if same version already applied ──
        // Done outside the transaction to avoid unnecessary locking on read-only checks.
        $existingComplete = ProvisioningRun::where('workspace_id', $workspaceId)
            ->where('blueprint_id', $blueprintId)
            ->whereIn('status', ['foundation_applied', 'applied'])
            ->first();

        if ($existingComplete && ($existingComplete->config['blueprint_version'] ?? null) === $blueprint->version) {
            return [
                'run_id'                    => $existingComplete->id,
                'status'                    => $existingComplete->status,
                'message'                   => 'This Blueprint version was already provisioned.',
                'blueprint_version'         => $blueprint->version,
                'already_foundation_applied' => true,
                'onboarding_completed'      => false,
            ];
        }

        // ── Build plan outside the transaction (deterministic, read-only) ──
        $plan = $this->planBuilder->build($blueprint, $workspaceId);
        $configMapping = $this->planBuilder->buildConfigMapping(
            $blueprint->blueprint,
            $blueprint->id,
            $blueprint->version,
        );

        // ═══════════════════════════════════════════════════════════════
        // ATOMIC CRITICAL SECTION
        // Everything below runs in one DB transaction:
        //   1. Acquire workspace-level pessimistic lock
        //   2. Check for active concurrent runs
        //   3. Create or resume prepared run
        //   4. Transition → processing
        //   5. Provision all 1.6B entities
        //   6. Save rollback snapshots
        //   7. Transition → foundation_applied
        //   8. Commit
        // ═══════════════════════════════════════════════════════════════
        try {
            return DB::transaction(function () use ($workspaceId, $blueprintId, $blueprint, $userId, $plan, $configMapping) {

                // 1. Acquire workspace-level pessimistic lock on provisioning_runs
                //    This prevents concurrent apply() calls for the same workspace.
                //    Different workspaces are unaffected — only rows matching $workspaceId are locked.
                $activeWorkspaceRun = ProvisioningRun::where('workspace_id', $workspaceId)
                    ->whereIn('status', ['processing', 'foundation_applied'])
                    ->lockForUpdate()
                    ->first();

                // 2. Reject if another run is active for this workspace
                if ($activeWorkspaceRun) {
                    return [
                        'run_id'     => $activeWorkspaceRun->id,
                        'status'     => $activeWorkspaceRun->status,
                        'message'    => 'A provisioning run is already active for this workspace. Complete or rollback it first.',
                        'active_run' => true,
                    ];
                }

                // 3. Find or create prepared run (with rollback snapshot)
                $run = ProvisioningRun::where('workspace_id', $workspaceId)
                    ->where('blueprint_id', $blueprintId)
                    ->where('status', 'prepared')
                    ->first();

                if (!$run) {
                    $rollbackSnapshot = $this->captureRollbackSnapshot($workspaceId);
                    $run = ProvisioningRun::create([
                        'workspace_id'    => $workspaceId,
                        'blueprint_id'    => $blueprintId,
                        'status'          => 'prepared',
                        'config'          => array_merge($plan, ['config_mapping' => $configMapping]),
                        'applied_by'      => $userId,
                        'version'         => $this->nextVersion($workspaceId),
                        'rollback_config' => $rollbackSnapshot,
                        'created_at'      => now(),
                    ]);
                }

                // 4. Transition to processing via state machine
                $run->transitionTo(ProvisioningRun::STATUS_PROCESSING);

                // 5. Provision all 1.6B entities
                $provisioner = new CoreEntityProvisioner();
                $result = $provisioner->provision(
                    $workspaceId,
                    $run->id,
                    $plan,
                    $blueprint->id,
                    $blueprint->version,
                );

                // 6. Merge rollback tracking into run
                $rollbackConfig = $run->rollback_config ?? [];
                $rollbackConfig['core_entities']             = $result['rollback_changes']['core_entities'] ?? [];
                $rollbackConfig['role_permissions_before']    = $result['rollback_changes']['role_permissions_before'] ?? [];
                $rollbackConfig['feature_flags_before']       = $result['rollback_changes']['feature_flags_before'] ?? [];
                $rollbackConfig['adopted_entity_snapshots']   = $result['rollback_changes']['adopted_entity_snapshots'] ?? [];

                // 7. Transition to foundation_applied via state machine
                $run->transitionTo(ProvisioningRun::STATUS_FOUNDATION_APPLIED, [
                    'config'          => array_merge($plan, [
                        'config_mapping'       => $configMapping,
                        'provisioning_result'  => [
                            'created' => $result['created'],
                            'updated' => $result['updated'],
                            'reused'  => $result['reused'],
                        ],
                    ]),
                    'rollback_config' => $rollbackConfig,
                    'applied_at'      => now(),
                ]);

                // 8. Commit (implicit on closure return)
                Log::info("Foundation provisioning completed for workspace {$workspaceId}, run {$run->id}");

                return [
                    'run_id'                => $run->id,
                    'status'                => 'foundation_applied',
                    'blueprint_id'          => $blueprint->id,
                    'blueprint_version'     => $blueprint->version,
                    'plan_summary'          => $plan['summary'],
                    'provisioning_result'   => [
                        'created' => $result['created'],
                        'updated' => $result['updated'],
                        'reused'  => $result['reused'],
                    ],
                    'warnings'              => array_merge($plan['warnings'], $result['warnings']),
                    'onboarding_completed'  => false,
                    'pending_phases'        => [
                        'operational_entities',
                        'business_settings',
                        'finalization',
                    ],
                ];
            });

        } catch (ProvisioningException $e) {
            // Expected domain error → mark failed via state machine, rethrow.
            // The run may exist from the transaction if it was created before the error.
            $failedRun = ProvisioningRun::where('workspace_id', $workspaceId)
                ->where('blueprint_id', $blueprintId)
                ->where('status', 'processing')
                ->first();
            if ($failedRun) {
                $failedRun->transitionTo(ProvisioningRun::STATUS_FAILED, [
                    'error_message' => $e->getMessage(),
                ]);
            }
            throw $e;

        } catch (\Throwable $e) {
            // Unexpected error → mark failed, log, throw safe ProvisioningException.
            Log::error("Provisioning failed for workspace {$workspaceId}: " . $e->getMessage());
            $failedRun = ProvisioningRun::where('workspace_id', $workspaceId)
                ->where('blueprint_id', $blueprintId)
                ->where('status', 'processing')
                ->first();
            if ($failedRun) {
                $failedRun->transitionTo(ProvisioningRun::STATUS_FAILED, [
                    'error_message' => 'Internal provisioning error. See server logs.',
                ]);
            }
            throw new ProvisioningException(
                'An internal error occurred during provisioning.',
                'internal_error',
                500,
                $e,
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Apply Operational — Task 1.6C
    // ═══════════════════════════════════════════════════════════════

    /**
     * Apply operational entities: warehouses, pipelines, approvals, commissions, settings.
     *
     * Continues from a foundation_applied run. On success transitions to 'applied'.
     * Does NOT finalize onboarding.
     */
    public function applyOperational(string $workspaceId, string $blueprintId, string $userId): array
    {
        $blueprint = $this->loadAndVerifyBlueprint($workspaceId, $blueprintId);
        $plan = $this->planBuilder->build($blueprint, $workspaceId);

        // ── Idempotency: return existing run if already fully applied ──
        $existingApplied = ProvisioningRun::where('workspace_id', $workspaceId)
            ->where('blueprint_id', $blueprintId)
            ->where('status', 'applied')
            ->first();

        if ($existingApplied && ($existingApplied->config['blueprint_version'] ?? null) === $blueprint->version) {
            return [
                'run_id'               => $existingApplied->id,
                'status'               => 'applied',
                'message'              => 'This Blueprint version was already fully provisioned.',
                'blueprint_version'    => $blueprint->version,
                'already_applied'      => true,
                'onboarding_completed' => false,
            ];
        }

        try {
            return DB::transaction(function () use ($workspaceId, $blueprintId, $blueprint, $userId, $plan) {

                // Find the foundation_applied run
                $run = ProvisioningRun::where('workspace_id', $workspaceId)
                    ->where('blueprint_id', $blueprintId)
                    ->where('status', 'foundation_applied')
                    ->lockForUpdate()
                    ->first();

                if (!$run) {
                    throw new ProvisioningException(
                        'No foundation_applied run found. Run apply() first to create core entities.',
                        'invalid_status_transition',
                        409,
                    );
                }

                // Provision operational entities
                $provisioner = new OperationalEntityProvisioner();
                $result = $provisioner->provision(
                    $workspaceId,
                    $run->id,
                    $plan,
                    $blueprint->id,
                    $blueprint->version,
                );

                // Merge operational rollback data into run config
                $rollbackConfig = $run->rollback_config ?? [];
                $rollbackConfig['operational_entities'] = $result['operational_entities'] ?? [];

                // Transition to applied
                $run->transitionTo(ProvisioningRun::STATUS_APPLIED, [
                    'config' => array_merge($run->config ?? [], [
                        'operational_result' => [
                            'created' => $result['created'],
                            'updated' => $result['updated'],
                        ],
                    ]),
                    'rollback_config' => $rollbackConfig,
                ]);

                Log::info("Operational provisioning completed for workspace {$workspaceId}, run {$run->id}");

                return [
                    'run_id'               => $run->id,
                    'status'               => 'applied',
                    'blueprint_id'         => $blueprint->id,
                    'blueprint_version'    => $blueprint->version,
                    'operational_result'   => [
                        'created' => $result['created'],
                        'updated' => $result['updated'],
                    ],
                    'warnings'             => $result['warnings'],
                    'blocked'              => $result['blocked'] ?? [],
                    'onboarding_completed' => false,
                ];
            });

        } catch (ProvisioningException $e) {
            throw $e;
        } catch (\Throwable $e) {
            Log::error("Operational provisioning failed for workspace {$workspaceId}: " . $e->getMessage());
            throw new ProvisioningException(
                'An internal error occurred during operational provisioning.',
                'internal_error',
                500,
                $e,
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Finalize — Task 1.6D (Onboarding Completion)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Finalize: assign primary_owner role to workspace owner, mark onboarding complete.
     *
     * Requires an 'applied' run. Resolves the primary_owner role dynamically through
     * provisioning bindings — never hardcodes a role key or name. Identifies the
     * workspace owner as the earliest-created active membership (established convention).
     *
     * Idempotent: if the run is already 'onboarding_complete', returns a cached success.
     *
     * @throws ProvisioningException on missing prerequisites or transition errors
     */
    public function finalize(string $workspaceId, string $runId, string $userId): array
    {
        // ── Idempotency: return immediately if already finalized ──
        $existingFinalized = ProvisioningRun::where('workspace_id', $workspaceId)
            ->where('id', $runId)
            ->where('status', ProvisioningRun::STATUS_ONBOARDING_COMPLETE)
            ->first();

        if ($existingFinalized) {
            return [
                'run_id'               => $existingFinalized->id,
                'status'               => 'onboarding_complete',
                'message'              => 'Onboarding was already finalized for this run.',
                'already_finalized'    => true,
                'onboarding_completed' => true,
            ];
        }

        try {
            $finalizedAt = now()->toIso8601String();

            $result = DB::transaction(function () use ($workspaceId, $runId, $userId, $finalizedAt) {

                // 1. Lock and load the run
                $run = ProvisioningRun::where('workspace_id', $workspaceId)
                    ->where('id', $runId)
                    ->lockForUpdate()
                    ->first();

                if (!$run) {
                    throw new ProvisioningException(
                        'Provisioning run not found in this workspace.',
                        'run_not_found',
                        404,
                    );
                }

                // 2. Verify status is 'applied' (state machine enforced)
                if ($run->status !== ProvisioningRun::STATUS_APPLIED) {
                    throw new ProvisioningException(
                        "Cannot finalize run in status '{$run->status}'. Only 'applied' runs can be finalized.",
                        'invalid_status_transition',
                        409,
                    );
                }

                // 3. Lock the workspace row to prevent concurrent finalization
                $workspace = Workspace::where('id', $workspaceId)
                    ->lockForUpdate()
                    ->first();

                if (!$workspace) {
                    throw new ProvisioningException(
                        'Workspace not found.',
                        'workspace_not_found',
                        404,
                    );
                }

                // 4. Resolve the primary_owner role from the Blueprint via provisioning bindings
                //    The Blueprint plan stores roles with is_primary_owner flag.
                //    Find the role key that was marked as primary_owner in the plan.
                $planRoles = $run->config['operations']['roles'] ?? [];
                $primaryOwnerKey = null;
                foreach ($planRoles as $role) {
                    if ($role['is_primary_owner'] ?? false) {
                        $primaryOwnerKey = $role['key'];
                        break;
                    }
                }

                if (!$primaryOwnerKey) {
                    throw new ProvisioningException(
                        'Blueprint does not define a role with is_primary_owner. Cannot finalize onboarding.',
                        'missing_primary_owner_role',
                        422,
                    );
                }

                // 5. Resolve the role entity ID through provisioning bindings
                $roleBinding = ProvisioningEntityBinding::where('workspace_id', $workspaceId)
                    ->where('entity_type', 'role')
                    ->where('local_key', $primaryOwnerKey)
                    ->first();

                if (!$roleBinding) {
                    throw new ProvisioningException(
                        "Primary owner role binding '{$primaryOwnerKey}' not found. Provisioning may be incomplete.",
                        'missing_role_binding',
                        422,
                    );
                }

                $primaryOwnerRoleId = $roleBinding->entity_id;

                // Verify the role entity actually exists
                $ownerRole = Role::where('id', $primaryOwnerRoleId)
                    ->where('workspace_id', $workspaceId)
                    ->first();

                if (!$ownerRole) {
                    throw new ProvisioningException(
                        "Primary owner role entity '{$primaryOwnerKey}' (id: {$primaryOwnerRoleId}) was deleted. Cannot finalize.",
                        'missing_bound_entity',
                        409,
                    );
                }

                // 6. Identify the workspace owner — earliest-created active membership
                $ownerMembership = WorkspaceMembership::where('workspace_id', $workspaceId)
                    ->where('status', 'active')
                    ->orderBy('created_at')
                    ->first();

                if (!$ownerMembership) {
                    throw new ProvisioningException(
                        'No active membership found for this workspace. Cannot assign owner role.',
                        'no_active_membership',
                        422,
                    );
                }

                // 7. Assign the primary_owner role to the owner membership (idempotent)
                $existingAssignment = MembershipRole::where('workspace_id', $workspaceId)
                    ->where('membership_id', $ownerMembership->id)
                    ->where('role_id', $primaryOwnerRoleId)
                    ->first();

                $roleAssigned = false;
                if (!$existingAssignment) {
                    MembershipRole::create([
                        'workspace_id'  => $workspaceId,
                        'membership_id' => $ownerMembership->id,
                        'role_id'       => $primaryOwnerRoleId,
                        'is_primary'    => true,
                        'assigned_by'   => $userId,
                        'assigned_at'   => now(),
                    ]);
                    $roleAssigned = true;
                } elseif (!$existingAssignment->is_primary) {
                    // Ensure is_primary is set even if already assigned
                    $existingAssignment->update(['is_primary' => true]);
                    $roleAssigned = true;
                }

                // 8. Mark onboarding complete in workspace.onboarding_data
                $onboardingData = $workspace->onboarding_data ?? [];
                $onboardingData['onboarding_completed']    = true;
                $onboardingData['onboarding_completed_at'] = $finalizedAt;
                $onboardingData['finalization_run_id']      = $run->id;
                $onboardingData['primary_owner_role_key']   = $primaryOwnerKey;
                $onboardingData['primary_owner_role_id']    = $primaryOwnerRoleId;
                $onboardingData['owner_membership_id']      = $ownerMembership->id;

                $workspace->update(['onboarding_data' => $onboardingData]);

                // 9. Transition to onboarding_complete via state machine
                $run->transitionTo(ProvisioningRun::STATUS_ONBOARDING_COMPLETE, [
                    'applied_by'  => $userId,
                    'applied_at'  => now(),
                ]);

                Log::info("Onboarding finalized for workspace {$workspaceId}, run {$run->id}, owner membership {$ownerMembership->id}");

                return [
                    'run_id'               => $run->id,
                    'status'               => 'onboarding_complete',
                    'workspace_id'         => $workspaceId,
                    'primary_owner_role'   => [
                        'key'  => $primaryOwnerKey,
                        'id'   => $primaryOwnerRoleId,
                        'name' => $ownerRole->name,
                    ],
                    'owner_membership'     => [
                        'id'      => $ownerMembership->id,
                        'user_id' => $ownerMembership->user_id,
                    ],
                    'role_assigned'        => $roleAssigned,
                    'onboarding_completed' => true,
                ];
            });

            // 10. Dispatch event AFTER transaction commits — exactly once
            //     The idempotent early-return path above never reaches here.
            WorkspaceOnboardingCompleted::dispatch(
                $workspaceId,
                $runId,
                $userId,
                $finalizedAt,
            );

            Log::info("WorkspaceOnboardingCompleted event dispatched for workspace {$workspaceId}, run {$runId}");

            return $result;

        } catch (ProvisioningException $e) {
            throw $e;
        } catch (\Throwable $e) {
            Log::error("Onboarding finalization failed for workspace {$workspaceId}, run {$runId}: " . $e->getMessage());
            throw new ProvisioningException(
                'An internal error occurred during onboarding finalization.',
                'internal_error',
                500,
                $e,
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Rollback
    // ═══════════════════════════════════════════════════════════════

    /**
     * Rollback: revert entities + config from a provisioned/prepared/failed run.
     *
     * Detects manual changes made after provisioning via snapshot comparison.
     * If any created entity has been modified since provisioning, throws
     * ProvisioningException with error code 'rollback_conflict' (409).
     *
     * If WorkspaceConfiguration did not exist before provisioning (snapshot is null),
     * it is deleted rather than restored to empty defaults.
     */
    public function rollback(string $workspaceId, string $runId, string $userId): array
    {
        return DB::transaction(function () use ($workspaceId, $runId, $userId) {
            $run = ProvisioningRun::where('workspace_id', $workspaceId)
                ->where('id', $runId)
                ->whereIn('status', ['foundation_applied', 'applied', 'prepared', 'failed'])
                ->firstOrFail();

            $rb = $run->rollback_config ?? [];
            $rollbackWarnings = [];

            // ── 0. Detect manual changes to provisioned entities (rollback_conflict) ──
            if (in_array($run->status, ['foundation_applied', 'applied'])) {
                $this->detectManualChanges($workspaceId, $rb, $run);
            }

            // ── 1a. Rollback operational entities (if applied) ──
            if (in_array($run->status, ['applied'])) {
                $this->rollbackOperationalEntities($workspaceId, $rb, $run->id);
            }

            // ── 1b. Rollback core entities (if foundation was applied) ──
            if (in_array($run->status, ['foundation_applied', 'applied', 'failed'])) {
                $rollbackWarnings = $this->rollbackCoreEntities($workspaceId, $rb, $run->id);
            }

            // ── 2. Restore feature flags ──
            $flagsBefore = $rb['feature_flags_before'] ?? $rb['feature_flags'] ?? [];
            if (!empty($flagsBefore)) {
                $this->restoreFeatureFlags($workspaceId, $flagsBefore);
            }

            // ── 3. Restore WorkspaceConfiguration ──
            $wcSnapshot = $rb['workspace_configuration'] ?? null;

            if ($wcSnapshot === null) {
                // WC didn't exist before provisioning — delete it entirely
                WorkspaceConfiguration::where('workspace_id', $workspaceId)->delete();
            } else {
                WorkspaceConfiguration::updateOrCreate(
                    ['workspace_id' => $workspaceId],
                    [
                        'enabled_modules'     => $wcSnapshot['enabled_modules'] ?? [],
                        'role_configs'        => $wcSnapshot['role_configs'] ?? [],
                        'pages'               => $wcSnapshot['pages'] ?? [],
                        'workflows'           => $wcSnapshot['workflows'] ?? [],
                        'automations'         => $wcSnapshot['automations'] ?? [],
                        'provisioning_run_id' => $wcSnapshot['provisioning_run_id'] ?? null,
                    ],
                );
            }

            // ── 4. Mark rolled back via state machine ──
            $run->transitionTo(ProvisioningRun::STATUS_ROLLED_BACK);

            Log::info("Provisioning rolled back for workspace {$workspaceId}, run {$runId}");

            return [
                'run_id'   => $run->id,
                'status'   => 'rolled_back',
                'warnings' => $rollbackWarnings,
            ];
        });
    }

    /**
     * Rollback core entities created/updated by provisioning.
     * Reverse dependency order: roles → teams → departments → locations.
     */
    private function rollbackCoreEntities(string $workspaceId, array $rb, string $runId): array
    {
        $warnings    = [];
        $coreData    = $rb['core_entities'] ?? [];
        $permsBefore = $rb['role_permissions_before'] ?? [];
        $adoptedSnapshots = $rb['adopted_entity_snapshots'] ?? [];

        // ── Restore updated role permissions ──
        foreach ($permsBefore as $localKey => $previousPermissions) {
            $binding = ProvisioningEntityBinding::where('workspace_id', $workspaceId)
                ->where('entity_type', 'role')
                ->where('local_key', $localKey)
                ->first();
            if ($binding) {
                $role = Role::find($binding->entity_id);
                if ($role) {
                    $role->update(['permissions' => $previousPermissions]);
                }
            }
        }

        // ── Delete created entities in reverse dependency order ──
        $deleteOrder = ['roles', 'teams', 'departments', 'locations'];
        $typeMap     = ['roles' => Role::class, 'teams' => Team::class, 'departments' => Department::class, 'locations' => Branch::class];
        $bindingTypeMap = ['roles' => 'role', 'teams' => 'team', 'departments' => 'department', 'locations' => 'location'];

        foreach ($deleteOrder as $group) {
            foreach ($coreData['created'][$group] ?? [] as $entry) {
                $entityId = $entry['id'];
                $modelClass = $typeMap[$group];
                $entity = $modelClass::where('workspace_id', $workspaceId)->where('id', $entityId)->first();

                if ($entity) {
                    $entity->delete();
                }

                // Remove binding
                ProvisioningEntityBinding::where('workspace_id', $workspaceId)
                    ->where('entity_type', $bindingTypeMap[$group])
                    ->where('entity_id', $entityId)
                    ->delete();
            }
        }

        // ── Restore adopted (reused) entities to their pre-provisioning state ──
        $entityTypeToModel = [
            'location'   => Branch::class,
            'department' => Department::class,
            'team'       => Team::class,
            'role'       => Role::class,
        ];

        foreach ($adoptedSnapshots as $snapshotKey => $snapshot) {
            [$entityType, $localKey] = explode(':', $snapshotKey, 2);
            $modelClass = $entityTypeToModel[$entityType] ?? null;

            if (!$modelClass || empty($snapshot['entity_id'])) {
                $warnings[] = "Cannot restore adopted {$entityType} '{$localKey}': unknown model.";
                continue;
            }

            $entity = $modelClass::where('workspace_id', $workspaceId)
                ->where('id', $snapshot['entity_id'])
                ->first();

            if ($entity) {
                $restoreData = $snapshot;
                unset($restoreData['entity_id']);
                $entity->update($restoreData);
            } else {
                $warnings[] = "Adopted {$entityType} '{$localKey}' (id: {$snapshot['entity_id']}) was deleted externally.";
            }

            // Remove the binding created during adoption
            ProvisioningEntityBinding::where('workspace_id', $workspaceId)
                ->where('entity_type', $entityType)
                ->where('local_key', $localKey)
                ->delete();
        }

        return $warnings;
    }

    /**
     * Rollback operational entities created by 1.6C provisioning.
     * Reverse dependency order: commission_rules → commission_plans → approval_workflow_steps →
     * approval_workflows → pipeline_stages → pipelines → warehouses.
     */
    private function rollbackOperationalEntities(string $workspaceId, array $rb, string $runId): void
    {
        $opData = $rb['operational_entities'] ?? [];
        $createdOps = $opData['created'] ?? [];

        // Entity types in reverse dependency order
        $deleteOrder = [
            'commission_rules'         => CommissionRule::class,
            'commission_plans'         => CommissionPlan::class,
            'approval_workflow_steps'  => ApprovalWorkflowStep::class,
            'approval_workflows'       => ApprovalWorkflow::class,
            'pipeline_stages'          => PipelineStage::class,
            'pipelines'                => Pipeline::class,
            'warehouses'               => Warehouse::class,
        ];

        foreach ($deleteOrder as $group => $modelClass) {
            foreach ($createdOps[$group] ?? [] as $entry) {
                $entityId = $entry['id'];
                $entity = $modelClass::where('workspace_id', $workspaceId)
                    ->where('id', $entityId)
                    ->first();

                if ($entity) {
                    $entity->delete();
                }

                // Remove binding — derive entity_type from group name
                $bindingType = rtrim($group, 's');
                // Fix plurals: pipeline_stages → pipeline_stage, commission_rules → commission_rule
                if (str_ends_with($group, 'ses')) {
                    // No groups end in 'ses' in our set
                } elseif (str_ends_with($group, 's')) {
                    $bindingType = substr($group, 0, -1);
                }

                ProvisioningEntityBinding::where('workspace_id', $workspaceId)
                    ->where('entity_type', $bindingType)
                    ->where('entity_id', $entityId)
                    ->delete();
            }
        }
    }

    /**
     * Detect if provisioned entities have been manually modified since provisioning.
     *
     * Compares current entity state against the provisioning result snapshot.
     * If any created entity has a different name than what was provisioned,
     * or if the WorkspaceConfiguration has been modified externally,
     * throws a ProvisioningException with error code 'rollback_conflict' (409).
     *
     * @throws ProvisioningException
     */
    private function detectManualChanges(string $workspaceId, array $rb, ProvisioningRun $run): void
    {
        $conflicts = [];
        $coreData = $rb['core_entities'] ?? [];
        $typeMap = [
            'roles'       => Role::class,
            'teams'       => Team::class,
            'departments' => Department::class,
            'locations'   => Branch::class,
        ];

        // Check provisioning_result in run config for the expected state
        $provResult = $run->config['provisioning_result'] ?? [];

        // Check created entities — compare current name vs provisioned name
        foreach (['roles', 'teams', 'departments', 'locations'] as $group) {
            $modelClass = $typeMap[$group];
            foreach ($coreData['created'][$group] ?? [] as $entry) {
                $entityId = $entry['id'];
                $entity = $modelClass::where('workspace_id', $workspaceId)
                    ->where('id', $entityId)
                    ->first();

                if (!$entity) {
                    // Entity deleted externally
                    $conflicts[] = ucfirst(rtrim($group, 's')) . " '{$entry['key']}' (id: {$entityId}) was deleted externally.";
                    continue;
                }

                // Check if entity was renamed since provisioning
                // We can detect this via the updated_at timestamp vs applied_at
                $appliedAt = $run->applied_at;
                if ($appliedAt && $entity->updated_at && $entity->updated_at->isAfter($appliedAt->addSeconds(2))) {
                    $conflicts[] = ucfirst(rtrim($group, 's')) . " '{$entry['key']}' was modified after provisioning.";
                }
            }
        }

        // Check if WorkspaceConfiguration was modified since provisioning
        $wc = WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
        if ($wc && $run->applied_at && $wc->provisioning_run_id !== $run->id) {
            $conflicts[] = "WorkspaceConfiguration was modified by a different process.";
        }

        if (!empty($conflicts)) {
            throw new ProvisioningException(
                'Rollback conflict: entities or configuration have been modified since provisioning. ' .
                'Manual review is required. Conflicts: ' . implode('; ', $conflicts),
                'rollback_conflict',
                409,
                null,
                ['conflicts' => $conflicts],
            );
        }
    }


    /**
     * Restore feature flags from rollback snapshot.
     */
    private function restoreFeatureFlags(string $workspaceId, array $flagsBefore): void
    {
        $values = array_values($flagsBefore);
        $isIndexedArray = !empty($values) && is_array($values[0] ?? null) && isset($values[0]['feature_key']);
        if ($isIndexedArray) {
            // Array of {feature_key, is_enabled} objects
            foreach ($flagsBefore as $flag) {
                if ($flag === null) continue;
                WorkspaceFeatureFlag::updateOrCreate(
                    ['workspace_id' => $workspaceId, 'feature_key' => $flag['feature_key']],
                    ['is_enabled' => $flag['is_enabled']],
                );
            }
        } else {
            // Keyed map: feature_key => {feature_key, is_enabled} or null
            foreach ($flagsBefore as $key => $state) {
                if ($state === null) {
                    // Flag didn't exist before — remove it
                    WorkspaceFeatureFlag::where('workspace_id', $workspaceId)
                        ->where('feature_key', $key)
                        ->delete();
                } else {
                    WorkspaceFeatureFlag::updateOrCreate(
                        ['workspace_id' => $workspaceId, 'feature_key' => $state['feature_key']],
                        ['is_enabled' => $state['is_enabled']],
                    );
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Config Query (preserved from 1.6A)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get active workspace configuration.
     */
    public function getActiveConfig(string $workspaceId): ?WorkspaceConfiguration
    {
        return WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
    }

    /**
     * Update module enablement.
     */
    public function updateModules(string $workspaceId, array $modules): WorkspaceConfiguration
    {
        $config = WorkspaceConfiguration::firstOrCreate(
            ['workspace_id' => $workspaceId],
            ['enabled_modules' => [], 'role_configs' => [], 'pages' => [], 'workflows' => [], 'automations' => []],
        );

        $config->update(['enabled_modules' => $modules]);
        return $config->fresh();
    }

    /**
     * Update a specific role's configuration.
     */
    public function updateRoleConfig(string $workspaceId, string $role, array $roleConfig): WorkspaceConfiguration
    {
        $config = WorkspaceConfiguration::firstOrCreate(
            ['workspace_id' => $workspaceId],
            ['enabled_modules' => [], 'role_configs' => [], 'pages' => [], 'workflows' => [], 'automations' => []],
        );

        $roles = $config->role_configs;
        $roles[$role] = array_merge($roles[$role] ?? [], $roleConfig);
        $config->update(['role_configs' => $roles]);

        return $config->fresh();
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private Helpers
    // ═══════════════════════════════════════════════════════════════

    /**
     * Load a Blueprint by ID and verify it belongs to the workspace.
     */
    private function loadAndVerifyBlueprint(string $workspaceId, string $blueprintId): DiscoveryBlueprint
    {
        $blueprint = DiscoveryBlueprint::where('workspace_id', $workspaceId)
            ->where('id', $blueprintId)
            ->firstOrFail();

        $bp = $blueprint->blueprint;

        // Reject legacy format
        if (BlueprintSchema::isLegacyFormat($bp)) {
            throw new ProvisioningException(
                'Blueprint uses legacy format. Regenerate using the canonical generator.',
                'legacy_format',
            );
        }

        // Reject unsupported schema version
        $version = $bp['schema_version'] ?? null;
        if ($version !== BlueprintSchema::VERSION) {
            throw new ProvisioningException(
                "Unsupported Blueprint schema version: {$version}. Expected: " . BlueprintSchema::VERSION,
                'unsupported_version',
            );
        }

        return $blueprint;
    }

    /**
     * Revalidate a Blueprint using the central validator.
     */
    private function revalidateBlueprint(DiscoveryBlueprint $blueprint): array
    {
        return $this->validator->validate($blueprint->blueprint);
    }

    /**
     * Capture a rollback snapshot of the current workspace state.
     */
    private function captureRollbackSnapshot(string $workspaceId): array
    {
        $wc = WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
        $featureFlags = WorkspaceFeatureFlag::where('workspace_id', $workspaceId)
            ->get()
            ->map(fn($f) => [
                'feature_key' => $f->feature_key,
                'is_enabled'  => $f->is_enabled,
            ])
            ->toArray();

        return [
            'captured_at' => now()->toISOString(),
            'workspace_configuration' => $wc ? [
                'enabled_modules'     => $wc->enabled_modules ?? [],
                'role_configs'        => $wc->role_configs ?? [],
                'pages'               => $wc->pages ?? [],
                'workflows'           => $wc->workflows ?? [],
                'automations'         => $wc->automations ?? [],
                'provisioning_run_id' => $wc->provisioning_run_id,
            ] : null,
            'feature_flags' => $featureFlags,
            'entity_counts' => $this->captureEntityCounts($workspaceId),
        ];
    }

    /**
     * Capture current entity counts for rollback reference.
     */
    private function captureEntityCounts(string $workspaceId): array
    {
        return [
            'roles'       => DB::table('roles')->where('workspace_id', $workspaceId)->count(),
            'departments' => DB::table('departments')->where('workspace_id', $workspaceId)->count(),
            'teams'       => DB::table('teams')->where('workspace_id', $workspaceId)->count(),
            'warehouses'  => DB::table('warehouses')->where('workspace_id', $workspaceId)->count(),
        ];
    }

    /**
     * Next version number for provisioning runs.
     */
    private function nextVersion(string $workspaceId): int
    {
        return (ProvisioningRun::where('workspace_id', $workspaceId)->max('version') ?? 0) + 1;
    }
}
