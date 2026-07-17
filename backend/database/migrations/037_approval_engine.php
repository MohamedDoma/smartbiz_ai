<?php

/**
 * Migration 037 — Universal Dynamic Approval Engine
 *
 * Creates the core approval infrastructure:
 *  - approval_workflows:      Reusable workflow definitions (multi-step, condition-driven)
 *  - approval_workflow_steps:  Ordered steps within a workflow (permission-based approver resolution)
 *  - approval_requests:       Individual approval requests linked to any entity
 *  - approval_request_steps:  Per-step tracking within a request
 *  - approval_decisions:      Immutable decision audit trail
 *
 * Design constraints:
 *  - Zero hardcoded role names — approver resolution is 100% permission-driven
 *  - Workspace-isolated — every row carries workspace_id for RLS
 *  - Backward-safe — no destructive changes to existing tables
 *  - Idempotent — safe to re-run via hasTable guards
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── approval_workflows ──────────────────────────────────────────

        if (!Schema::hasTable('approval_workflows')) {
            Schema::create('approval_workflows', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->string('workflow_key', 100);              // e.g. "commission_approval", "invoice_approval"
                $table->string('name', 255);                       // Human-readable name
                $table->text('description')->nullable();
                $table->string('entity_type', 100);                // e.g. "commission_entry", "invoice", "expense"
                $table->jsonb('trigger_conditions')->default('{}'); // JSON conditions for auto-triggering
                $table->boolean('is_active')->default(true);
                $table->integer('sort_order')->default(0);
                $table->uuid('created_by')->nullable();            // membership_id of creator
                $table->timestamps();

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->unique(['workspace_id', 'workflow_key'], 'uq_aw_ws_key');
                $table->index(['workspace_id', 'entity_type', 'is_active'], 'idx_aw_entity_active');
            });
        }

        // ── approval_workflow_steps ─────────────────────────────────────

        if (!Schema::hasTable('approval_workflow_steps')) {
            Schema::create('approval_workflow_steps', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('workflow_id');
                $table->string('name', 255);                                        // Step display name
                $table->integer('step_order');                                       // Execution order (1, 2, 3...)
                $table->string('approver_type', 50);                                 // 'permission' | 'requester_manager' | 'specific_membership'
                $table->string('approver_permission_key', 100)->nullable();          // Required when approver_type='permission'
                $table->uuid('approver_membership_id')->nullable();                  // Required when approver_type='specific_membership'
                $table->jsonb('conditions')->default('{}');                          // Optional JSON conditions for step applicability
                $table->boolean('allow_self_approval')->default(false);              // Can the requester approve their own request at this step?
                $table->boolean('is_active')->default(true);
                $table->timestamps();

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('workflow_id')
                      ->references('id')->on('approval_workflows')
                      ->onDelete('cascade');

                $table->unique(['workflow_id', 'step_order'], 'uq_aws_workflow_order');
                $table->index(['workspace_id', 'workflow_id', 'is_active'], 'idx_aws_wf_active');
            });
        }

        // ── approval_requests ───────────────────────────────────────────

        if (!Schema::hasTable('approval_requests')) {
            Schema::create('approval_requests', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('workflow_id');
                $table->string('entity_type', 100);                // Denormalized for fast queries
                $table->uuid('entity_id');                         // The record being approved
                $table->uuid('requester_membership_id');           // Who submitted the request
                $table->string('status', 30)->default('pending');  // pending | approved | rejected | cancelled
                $table->integer('current_step_order')->default(1); // Which step is active
                $table->jsonb('entity_snapshot')->default('{}');    // Snapshot of entity data at request time
                $table->jsonb('metadata')->default('{}');           // Additional context
                $table->text('final_notes')->nullable();
                $table->timestamp('resolved_at')->nullable();
                $table->timestamps();

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('workflow_id')
                      ->references('id')->on('approval_workflows')
                      ->onDelete('restrict');

                $table->foreign('requester_membership_id')
                      ->references('id')->on('workspace_memberships')
                      ->onDelete('restrict');

                $table->index(['workspace_id', 'status'], 'idx_ar_ws_status');
                $table->index(['workspace_id', 'entity_type', 'entity_id'], 'idx_ar_entity');
                $table->index(['workspace_id', 'requester_membership_id', 'status'], 'idx_ar_requester');
            });
        }

        // ── approval_request_steps ──────────────────────────────────────

        if (!Schema::hasTable('approval_request_steps')) {
            Schema::create('approval_request_steps', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('approval_request_id');
                $table->uuid('workflow_step_id');
                $table->integer('step_order');                       // Denormalized from workflow_step
                $table->string('status', 30)->default('pending');    // pending | approved | rejected | skipped
                $table->uuid('decided_by_membership_id')->nullable();
                $table->text('decision_notes')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->timestamps();

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('approval_request_id')
                      ->references('id')->on('approval_requests')
                      ->onDelete('cascade');

                $table->foreign('workflow_step_id')
                      ->references('id')->on('approval_workflow_steps')
                      ->onDelete('restrict');

                $table->index(['workspace_id', 'approval_request_id', 'step_order'], 'idx_ars_req_order');
                $table->index(['workspace_id', 'status'], 'idx_ars_ws_status');
            });
        }

        // ── approval_decisions (immutable audit trail) ──────────────────

        if (!Schema::hasTable('approval_decisions')) {
            Schema::create('approval_decisions', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('approval_request_id');
                $table->uuid('approval_request_step_id');
                $table->uuid('actor_membership_id');                 // Who made the decision
                $table->string('decision', 20);                      // 'approved' | 'rejected'
                $table->text('notes')->nullable();
                $table->jsonb('actor_snapshot')->default('{}');       // Snapshot: actor name, role, permissions at decision time
                $table->timestamp('created_at')->useCurrent();

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('approval_request_id')
                      ->references('id')->on('approval_requests')
                      ->onDelete('cascade');

                $table->foreign('approval_request_step_id')
                      ->references('id')->on('approval_request_steps')
                      ->onDelete('cascade');

                $table->foreign('actor_membership_id')
                      ->references('id')->on('workspace_memberships')
                      ->onDelete('restrict');

                $table->index(['workspace_id', 'approval_request_id'], 'idx_ad_req');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('approval_decisions');
        Schema::dropIfExists('approval_request_steps');
        Schema::dropIfExists('approval_requests');
        Schema::dropIfExists('approval_workflow_steps');
        Schema::dropIfExists('approval_workflows');
    }
};
