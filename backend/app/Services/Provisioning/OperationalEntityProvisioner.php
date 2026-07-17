<?php

namespace App\Services\Provisioning;

use App\Exceptions\ProvisioningException;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Models\ProvisioningEntityBinding;
use App\Models\Warehouse;
use App\Models\Workspace;
use App\Services\Blueprint\BlueprintSchema;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Operational Entity Provisioner — Task 1.6C.
 *
 * Provisions operational entities from a validated Blueprint plan,
 * continuing from a foundation_applied run:
 *   1. Warehouses (linked to provisioned branches)
 *   2. Pipelines + ordered stages
 *   3. Approval workflows + steps
 *   4. Commission plans + rules (role-resolved via bindings)
 *   5. Workspace settings (currency, timezone, locale)
 *
 * All operations run inside a single DB transaction.
 * Does NOT create approval requests, invoices, payments, contacts, products, or transactions.
 * Does NOT finalize onboarding.
 */
class OperationalEntityProvisioner
{
    private string $workspaceId;
    private string $runId;
    private string $blueprintId;
    private int    $blueprintVersion;

    /** @var array<string,ProvisioningEntityBinding> All workspace bindings keyed by "type:localKey" */
    private array $bindings = [];

    /** @var array Tracking for result/rollback */
    private array $created  = [];
    private array $updated  = [];
    private array $warnings = [];
    private array $blocked  = [];

    /**
     * Test-only failure injection hook.
     * @internal Test infrastructure only.
     * @var \Closure|null
     */
    private static ?\Closure $testFailureHook = null;

    /**
     * Provision operational entities from a validated plan.
     *
     * @param  string $workspaceId
     * @param  string $runId
     * @param  array  $plan        The full plan from ProvisioningPlanBuilder
     * @param  string $blueprintId
     * @param  int    $blueprintVersion
     * @return array  Structured result with created/updated/warnings/blocked
     * @throws ProvisioningException on reference resolution failures
     */
    public function provision(
        string $workspaceId,
        string $runId,
        array  $plan,
        string $blueprintId,
        int    $blueprintVersion,
    ): array {
        $this->workspaceId      = $workspaceId;
        $this->runId            = $runId;
        $this->blueprintId      = $blueprintId;
        $this->blueprintVersion = $blueprintVersion;

        $operations = $plan['operations'] ?? $plan;

        // Load all existing bindings (includes 1.6B core bindings)
        $this->loadExistingBindings();

        // 1. Warehouses
        $this->provisionWarehouses($operations['warehouses'] ?? []);

        // ── Test-only failure injection point ──
        if (self::$testFailureHook !== null) {
            (self::$testFailureHook)($this);
        }

        // 2. Pipelines + stages
        $this->provisionPipelines($operations['pipelines'] ?? []);

        // 3. Approval workflows + steps
        $this->provisionApprovalWorkflows($operations['approval_workflows'] ?? []);

        // 4. Commission plans + rules
        $this->provisionCommissionRules($operations['commission_rules'] ?? []);

        // 5. Settings
        $settingsResult = $this->provisionSettings($operations, $plan);

        return [
            'created'  => $this->created,
            'updated'  => $this->updated,
            'warnings' => $this->warnings,
            'blocked'  => $this->blocked,
            'operational_entities' => [
                'created' => $this->created,
                'updated' => $this->updated,
            ],
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  1. Warehouses
    // ═══════════════════════════════════════════════════════════════

    private function provisionWarehouses(array $warehouses): void
    {
        foreach ($warehouses as $idx => $wh) {
            $localKey = $wh['key'];

            // Resolve branch binding from location_key
            $branchId = null;
            if (!empty($wh['location_key'])) {
                $locBinding = $this->findBinding('location', $wh['location_key']);
                if (!$locBinding) {
                    throw new ProvisioningException(
                        "Warehouse '{$localKey}': location_key '{$wh['location_key']}' not found in provisioning bindings.",
                        'unresolved_reference',
                        422,
                        null,
                        ['entity_type' => 'warehouse', 'local_key' => $localKey, 'missing_ref' => $wh['location_key']],
                    );
                }
                $branchId = $locBinding->entity_id;
            }

            // Check existing binding
            $binding = $this->findBinding('warehouse', $localKey);

            if ($binding) {
                $entity = Warehouse::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'      => $wh['name'],
                        'branch_id' => $branchId,
                        'location'  => $wh['address'] ?? $wh['location'] ?? null,
                    ]);
                    $this->updated['warehouses'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                $this->throwMissingBoundEntity('warehouse', $localKey, $binding->entity_id);
            }

            // Create new warehouse
            $entity = Warehouse::create([
                'workspace_id' => $this->workspaceId,
                'name'         => $wh['name'],
                'branch_id'    => $branchId,
                'location'     => $wh['address'] ?? $wh['location'] ?? null,
            ]);

            $this->createBinding('warehouse', $localKey, $entity->id);
            $this->created['warehouses'][] = ['key' => $localKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  2. Pipelines + Stages
    // ═══════════════════════════════════════════════════════════════

    private function provisionPipelines(array $pipelines): void
    {
        foreach ($pipelines as $pIdx => $pl) {
            $localKey = $pl['key'];

            // Validate entity_type
            $entityType = $pl['entity_type'] ?? 'deal';
            if (!in_array($entityType, BlueprintSchema::PIPELINE_ENTITY_TYPES, true)) {
                throw new ProvisioningException(
                    "Pipeline '{$localKey}': invalid entity_type '{$entityType}'.",
                    'invalid_entity_type',
                    422,
                    null,
                    ['entity_type' => 'pipeline', 'local_key' => $localKey],
                );
            }

            $binding = $this->findBinding('pipeline', $localKey);

            if ($binding) {
                $entity = Pipeline::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'        => $pl['name'],
                        'description' => $pl['description'] ?? null,
                        'entity_type' => $entityType,
                        'is_active'   => true,
                        'sort_order'  => $pIdx,
                    ]);
                    $this->updated['pipelines'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    $this->provisionStages($entity, $pl['stages'] ?? [], $localKey);
                    continue;
                }
                $this->throwMissingBoundEntity('pipeline', $localKey, $binding->entity_id);
            }

            // Create new pipeline
            $entity = Pipeline::create([
                'workspace_id' => $this->workspaceId,
                'pipeline_key' => $localKey,
                'name'         => $pl['name'],
                'description'  => $pl['description'] ?? null,
                'entity_type'  => $entityType,
                'is_active'    => true,
                'sort_order'   => $pIdx,
            ]);

            $this->createBinding('pipeline', $localKey, $entity->id);
            $this->created['pipelines'][] = ['key' => $localKey, 'id' => $entity->id];

            // Provision stages
            $this->provisionStages($entity, $pl['stages'] ?? [], $localKey);
        }
    }

    private function provisionStages(Pipeline $pipeline, array $stages, string $pipelineLocalKey): void
    {
        foreach ($stages as $sIdx => $stage) {
            $stageLocalKey = $stage['key'] ?? "{$pipelineLocalKey}_stage_{$sIdx}";
            $compositeKey  = "{$pipelineLocalKey}.{$stageLocalKey}";

            $statusType = $stage['status_type'] ?? $stage['type'] ?? 'open';
            // Normalize common aliases
            $statusMap = ['active' => 'open', 'closed' => 'completed'];
            $statusType = $statusMap[$statusType] ?? $statusType;

            $binding = $this->findBinding('pipeline_stage', $compositeKey);

            if ($binding) {
                $entity = PipelineStage::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'        => $stage['name'],
                        'description' => $stage['description'] ?? null,
                        'status_type' => $statusType,
                        'sort_order'  => $sIdx,
                        'is_active'   => true,
                    ]);
                    $this->updated['pipeline_stages'][] = ['key' => $compositeKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                $this->throwMissingBoundEntity('pipeline_stage', $compositeKey, $binding->entity_id);
            }

            $entity = PipelineStage::create([
                'workspace_id' => $this->workspaceId,
                'pipeline_id'  => $pipeline->id,
                'stage_key'    => $stageLocalKey,
                'name'         => $stage['name'],
                'description'  => $stage['description'] ?? null,
                'status_type'  => $statusType,
                'sort_order'   => $sIdx,
                'is_active'    => true,
            ]);

            $this->createBinding('pipeline_stage', $compositeKey, $entity->id);
            $this->created['pipeline_stages'][] = ['key' => $compositeKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  3. Approval Workflows + Steps
    // ═══════════════════════════════════════════════════════════════

    private function provisionApprovalWorkflows(array $workflows): void
    {
        foreach ($workflows as $wIdx => $wf) {
            $localKey = $wf['key'];

            $entityType = $wf['entity_type'] ?? 'invoice';
            if (!in_array($entityType, BlueprintSchema::APPROVAL_ENTITY_TYPES, true)) {
                throw new ProvisioningException(
                    "Approval workflow '{$localKey}': invalid entity_type '{$entityType}'.",
                    'invalid_entity_type',
                    422,
                    null,
                    ['entity_type' => 'approval_workflow', 'local_key' => $localKey],
                );
            }

            // Determine if workflow should be active
            $requiresConfig = !empty($wf['requires_configuration']);
            $isActive = !$requiresConfig;

            $binding = $this->findBinding('approval_workflow', $localKey);

            if ($binding) {
                $entity = ApprovalWorkflow::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'               => $wf['name'],
                        'description'        => $wf['description'] ?? null,
                        'entity_type'        => $entityType,
                        'trigger_conditions' => $wf['trigger_conditions'] ?? $wf['conditions'] ?? [],
                        'is_active'          => $isActive,
                        'sort_order'         => $wIdx,
                    ]);
                    $this->updated['approval_workflows'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    $this->provisionWorkflowSteps($entity, $wf['steps'] ?? [], $localKey);
                    continue;
                }
                $this->throwMissingBoundEntity('approval_workflow', $localKey, $binding->entity_id);
            }

            $entity = ApprovalWorkflow::create([
                'workspace_id'       => $this->workspaceId,
                'workflow_key'       => $localKey,
                'name'               => $wf['name'],
                'description'        => $wf['description'] ?? null,
                'entity_type'        => $entityType,
                'trigger_conditions' => $wf['trigger_conditions'] ?? $wf['conditions'] ?? [],
                'is_active'          => $isActive,
                'sort_order'         => $wIdx,
            ]);

            $this->createBinding('approval_workflow', $localKey, $entity->id);
            $this->created['approval_workflows'][] = ['key' => $localKey, 'id' => $entity->id, 'active' => $isActive];

            if ($requiresConfig) {
                $this->warnings[] = "Approval workflow '{$localKey}' created as inactive — requires configuration.";
            }

            $this->provisionWorkflowSteps($entity, $wf['steps'] ?? [], $localKey);
        }
    }

    private function provisionWorkflowSteps(ApprovalWorkflow $workflow, array $steps, string $wfLocalKey): void
    {
        foreach ($steps as $sIdx => $step) {
            $stepLocalKey  = $step['key'] ?? "{$wfLocalKey}_step_{$sIdx}";
            $compositeKey  = "{$wfLocalKey}.{$stepLocalKey}";

            $approverType = $step['approver_type'] ?? 'permission';

            // Resolve approver_permission_key if present
            $approverPermKey = $step['approver_permission_key'] ?? null;

            // Resolve role_key → role binding for specific_membership type (not used in provisioning)
            $approverMembershipId = null;

            $binding = $this->findBinding('approval_workflow_step', $compositeKey);

            if ($binding) {
                $entity = ApprovalWorkflowStep::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'                    => $step['name'],
                        'step_order'              => $sIdx,
                        'approver_type'           => $approverType,
                        'approver_permission_key' => $approverPermKey,
                        'conditions'              => $step['conditions'] ?? [],
                        'allow_self_approval'     => $step['allow_self_approval'] ?? false,
                        'is_active'               => true,
                    ]);
                    $this->updated['approval_workflow_steps'][] = ['key' => $compositeKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                $this->throwMissingBoundEntity('approval_workflow_step', $compositeKey, $binding->entity_id);
            }

            $entity = ApprovalWorkflowStep::create([
                'workspace_id'            => $this->workspaceId,
                'workflow_id'             => $workflow->id,
                'name'                    => $step['name'],
                'step_order'              => $sIdx,
                'approver_type'           => $approverType,
                'approver_permission_key' => $approverPermKey,
                'approver_membership_id'  => $approverMembershipId,
                'conditions'              => $step['conditions'] ?? [],
                'allow_self_approval'     => $step['allow_self_approval'] ?? false,
                'is_active'               => true,
            ]);

            $this->createBinding('approval_workflow_step', $compositeKey, $entity->id);
            $this->created['approval_workflow_steps'][] = ['key' => $compositeKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  4. Commission Plans + Rules
    // ═══════════════════════════════════════════════════════════════

    private function provisionCommissionRules(array $commissionRules): void
    {
        foreach ($commissionRules as $cIdx => $cr) {
            $localKey = $cr['key'];

            // Create or update commission plan
            $planBinding = $this->findBinding('commission_plan', $localKey);
            $plan = null;

            if ($planBinding) {
                $plan = CommissionPlan::where('workspace_id', $this->workspaceId)
                    ->where('id', $planBinding->entity_id)
                    ->first();

                if ($plan) {
                    $plan->update([
                        'name'        => $cr['name'],
                        'description' => $cr['description'] ?? null,
                        'applies_to'  => $cr['applies_to'] ?? 'deal',
                        'is_active'   => true,
                        'sort_order'  => $cIdx,
                    ]);
                    $this->updated['commission_plans'][] = ['key' => $localKey, 'id' => $plan->id];
                    $this->updateBinding($planBinding);
                } else {
                    $this->throwMissingBoundEntity('commission_plan', $localKey, $planBinding->entity_id);
                }
            } else {
                $plan = CommissionPlan::create([
                    'workspace_id' => $this->workspaceId,
                    'plan_key'     => $localKey,
                    'name'         => $cr['name'],
                    'description'  => $cr['description'] ?? null,
                    'applies_to'   => $cr['applies_to'] ?? 'deal',
                    'is_active'    => true,
                    'sort_order'   => $cIdx,
                ]);
                $this->createBinding('commission_plan', $localKey, $plan->id);
                $this->created['commission_plans'][] = ['key' => $localKey, 'id' => $plan->id];
            }

            // Provision individual rules within this plan
            foreach ($cr['rules'] ?? [] as $rIdx => $rule) {
                $ruleLocalKey = $rule['key'] ?? "{$localKey}_rule_{$rIdx}";
                $compositeKey = "{$localKey}.{$ruleLocalKey}";

                // Resolve role_key → role ID via binding
                $roleId = null;
                if (!empty($rule['role_key'])) {
                    $roleBinding = $this->findBinding('role', $rule['role_key']);
                    if (!$roleBinding) {
                        throw new ProvisioningException(
                            "Commission rule '{$compositeKey}': role_key '{$rule['role_key']}' not found in provisioning bindings.",
                            'unresolved_reference',
                            422,
                            null,
                            ['entity_type' => 'commission_rule', 'local_key' => $compositeKey, 'missing_ref' => $rule['role_key']],
                        );
                    }
                    $roleId = $roleBinding->entity_id;
                }

                // Resolve pipeline_key → pipeline ID via binding
                $pipelineId = null;
                if (!empty($rule['pipeline_key'])) {
                    $plBinding = $this->findBinding('pipeline', $rule['pipeline_key']);
                    if (!$plBinding) {
                        throw new ProvisioningException(
                            "Commission rule '{$compositeKey}': pipeline_key '{$rule['pipeline_key']}' not found in provisioning bindings.",
                            'unresolved_reference',
                            422,
                            null,
                            ['entity_type' => 'commission_rule', 'local_key' => $compositeKey, 'missing_ref' => $rule['pipeline_key']],
                        );
                    }
                    $pipelineId = $plBinding->entity_id;
                }

                $calculationType = $rule['calculation_type'] ?? $rule['model'] ?? 'percentage';
                if (!in_array($calculationType, BlueprintSchema::COMMISSION_MODELS, true)) {
                    $calculationType = 'percentage';
                }

                $ruleBinding = $this->findBinding('commission_rule', $compositeKey);

                if ($ruleBinding) {
                    $ruleEntity = CommissionRule::where('workspace_id', $this->workspaceId)
                        ->where('id', $ruleBinding->entity_id)
                        ->first();

                    if ($ruleEntity) {
                        $ruleEntity->update([
                            'role_id'          => $roleId,
                            'pipeline_id'      => $pipelineId,
                            'target_type'      => $rule['target_type'] ?? 'deal',
                            'calculation_type' => $calculationType,
                            'percentage_rate'  => $rule['percentage_rate'] ?? $rule['rate'] ?? null,
                            'fixed_amount'     => $rule['fixed_amount'] ?? null,
                            'currency'         => $rule['currency'] ?? null,
                            'trigger_status'   => $rule['trigger_status'] ?? 'won',
                            'is_active'        => true,
                            'sort_order'       => $rIdx,
                        ]);
                        $this->updated['commission_rules'][] = ['key' => $compositeKey, 'id' => $ruleEntity->id];
                        $this->updateBinding($ruleBinding);
                        continue;
                    }
                    $this->throwMissingBoundEntity('commission_rule', $compositeKey, $ruleBinding->entity_id);
                }

                $ruleEntity = CommissionRule::create([
                    'workspace_id'       => $this->workspaceId,
                    'commission_plan_id' => $plan->id,
                    'role_id'            => $roleId,
                    'pipeline_id'        => $pipelineId,
                    'target_type'        => $rule['target_type'] ?? 'deal',
                    'calculation_type'   => $calculationType,
                    'percentage_rate'    => $rule['percentage_rate'] ?? $rule['rate'] ?? null,
                    'fixed_amount'       => $rule['fixed_amount'] ?? null,
                    'currency'           => $rule['currency'] ?? null,
                    'trigger_status'     => $rule['trigger_status'] ?? 'won',
                    'is_active'          => true,
                    'sort_order'         => $rIdx,
                ]);

                $this->createBinding('commission_rule', $compositeKey, $ruleEntity->id);
                $this->created['commission_rules'][] = ['key' => $compositeKey, 'id' => $ruleEntity->id];
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  5. Settings
    // ═══════════════════════════════════════════════════════════════

    private function provisionSettings(array $operations, array $plan): void
    {
        $wsSettings = $operations['workspace_settings'] ?? [];
        if (empty($wsSettings)) return;

        // Map Blueprint settings → workspace table columns
        $settingsMap = [
            'currency'         => 'default_currency',
            'timezone'         => 'timezone',
            'primary_language' => 'default_locale',
        ];

        $workspace = Workspace::find($this->workspaceId);
        if (!$workspace) return;

        $updates = [];
        foreach ($wsSettings as $field => $value) {
            if (isset($settingsMap[$field]) && $value !== null) {
                $updates[$settingsMap[$field]] = $value;
            } elseif ($field === 'country') {
                // No direct workspace column — skip silently (handled by localization)
                continue;
            } elseif ($field === 'business_type') {
                $updates['industry_type'] = $value;
            } elseif ($field === 'business_name') {
                $updates['name'] = $value;
            } elseif (!in_array($field, ['country', 'business_type', 'business_name', 'currency', 'timezone', 'primary_language'])) {
                $this->blocked[] = ['field' => $field, 'reason' => 'No valid persistence target'];
                $this->warnings[] = "Setting '{$field}' BLOCKED — no valid persistence target in the database.";
            }
        }

        if (!empty($updates)) {
            $workspace->update($updates);
            $this->created['settings'] = array_keys($updates);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private Helpers
    // ═══════════════════════════════════════════════════════════════

    private function loadExistingBindings(): void
    {
        $bindings = ProvisioningEntityBinding::where('workspace_id', $this->workspaceId)->get();
        foreach ($bindings as $b) {
            $this->bindings["{$b->entity_type}:{$b->local_key}"] = $b;
        }
    }

    private function findBinding(string $type, string $localKey): ?ProvisioningEntityBinding
    {
        return $this->bindings["{$type}:{$localKey}"] ?? null;
    }

    private function createBinding(
        string $type,
        string $localKey,
        string $entityId,
        string $ownershipType = ProvisioningEntityBinding::OWNERSHIP_CREATED_BY_PROVISIONING,
    ): void {
        $binding = ProvisioningEntityBinding::updateOrCreate(
            [
                'workspace_id' => $this->workspaceId,
                'entity_type'  => $type,
                'local_key'    => $localKey,
            ],
            [
                'entity_id'                => $entityId,
                'ownership_type'           => $ownershipType,
                'last_provisioning_run_id' => $this->runId,
                'last_blueprint_id'        => $this->blueprintId,
                'last_blueprint_version'   => $this->blueprintVersion,
            ],
        );
        $this->bindings["{$type}:{$localKey}"] = $binding;
    }

    private function updateBinding(ProvisioningEntityBinding $binding): void
    {
        $binding->update([
            'last_provisioning_run_id' => $this->runId,
            'last_blueprint_id'        => $this->blueprintId,
            'last_blueprint_version'   => $this->blueprintVersion,
        ]);
    }

    private function throwMissingBoundEntity(string $entityType, string $localKey, string $entityId): void
    {
        throw new ProvisioningException(
            "Provisioning conflict: {$entityType} '{$localKey}' is bound to entity {$entityId}, but that entity no longer exists.",
            'missing_bound_entity',
            409,
            null,
            ['entity_type' => $entityType, 'local_key' => $localKey, 'entity_id' => $entityId],
        );
    }
}
