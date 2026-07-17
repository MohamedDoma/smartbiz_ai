<?php

/**
 * Migration 037b — Remediate approval_requests table schema.
 *
 * The approval_requests table was created by an earlier migration with a
 * simplified schema. Migration 037 could not recreate it due to its
 * hasTable guard. This migration drops the old (empty) table and recreates
 * it with the correct schema needed by the ApprovalEngine.
 *
 * Safe to run: only drops if no existing rows AND schema mismatches.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Only remediate if the table exists but is missing the workflow_id column
        if (Schema::hasTable('approval_requests') && !Schema::hasColumn('approval_requests', 'workflow_id')) {

            $rowCount = DB::table('approval_requests')->count();

            if ($rowCount > 0) {
                echo "⚠️  approval_requests has {$rowCount} rows — skipping destructive remediation.\n";
                echo "    Manual migration required to preserve data.\n";
                return;
            }

            echo "Remediating approval_requests table (0 rows, old schema)...\n";

            // Drop in reverse FK-dependency order
            Schema::dropIfExists('approval_decisions');       // depends on request_steps + requests
            Schema::dropIfExists('approval_request_steps');   // depends on requests
            Schema::dropIfExists('approval_requests');

            // Recreate with correct schema
            Schema::create('approval_requests', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('workflow_id');
                $table->string('entity_type', 100);
                $table->uuid('entity_id');
                $table->uuid('requester_membership_id');
                $table->string('status', 30)->default('pending');
                $table->integer('current_step_order')->default(1);
                $table->jsonb('entity_snapshot')->default('{}');
                $table->jsonb('metadata')->default('{}');
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

            echo "✓ approval_requests recreated with correct schema\n";

            // Recreate approval_request_steps
            if (!Schema::hasTable('approval_request_steps')) {
                Schema::create('approval_request_steps', function (Blueprint $table) {
                    $table->uuid('id')->primary();
                    $table->uuid('workspace_id');
                    $table->uuid('approval_request_id');
                    $table->uuid('workflow_step_id');
                    $table->integer('step_order');
                    $table->string('status', 30)->default('pending');
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

                echo "✓ approval_request_steps recreated\n";
            }

            // Recreate approval_decisions
            if (!Schema::hasTable('approval_decisions')) {
                Schema::create('approval_decisions', function (Blueprint $table) {
                    $table->uuid('id')->primary();
                    $table->uuid('workspace_id');
                    $table->uuid('approval_request_id');
                    $table->uuid('approval_request_step_id');
                    $table->uuid('actor_membership_id');
                    $table->string('decision', 20);
                    $table->text('notes')->nullable();
                    $table->jsonb('actor_snapshot')->default('{}');
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

                echo "✓ approval_decisions recreated\n";
            }

            echo "✅ Remediation complete.\n";

        } else {
            echo "approval_requests schema is correct — no remediation needed.\n";
        }
    }

    public function down(): void
    {
        // Remediation is non-reversible — the old schema was incorrect.
        // down() is a no-op to avoid data loss.
    }
};
