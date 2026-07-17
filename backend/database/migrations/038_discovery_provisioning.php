<?php

/**
 * Migration 038 — Discovery, Provisioning & Workspace Configuration Tables
 *
 * Creates the five missing tables for the AI Discovery → Blueprint →
 * Provisioning pipeline:
 *
 *  1. discovery_sessions          — One session per business onboarding/discovery
 *  2. discovery_messages          — AI + user conversation log (ordered by created_at)
 *  3. discovery_blueprints        — Generated ERP blueprint (one per session)
 *  4. provisioning_runs           — Preview / apply / rollback / failed runs
 *  5. workspace_configurations    — Current provisioned workspace config (one per workspace)
 *
 * Design constraints:
 *  - Matches existing Eloquent models ($fillable, $casts, relationships)
 *  - Matches architecture SQL (015_ai_discovery.sql, 018_provisioning_manual_payments.sql)
 *  - UUID primary keys consistent with all other SmartBiz tables
 *  - Workspace-isolated — every row carries workspace_id
 *  - Idempotent — safe to re-run via hasTable guards
 *  - Rollback drops in reverse dependency order
 *
 * Status vocabulary for provisioning_runs:
 *  - preview     — dry-run config generation
 *  - applied     — successfully provisioned (terminal success)
 *  - rolled_back — reverted to previous config
 *  - failed      — error during provisioning
 *
 * References:
 *  - app/Models/DiscoverySession.php
 *  - app/Models/DiscoveryMessage.php
 *  - app/Models/DiscoveryBlueprint.php
 *  - app/Models/ProvisioningRun.php
 *  - app/Models/WorkspaceConfiguration.php
 *  - app/Services/DiscoverySessionService.php
 *  - app/Services/ProvisioningService.php
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ═══════════════════════════════════════════════════════════════
        //  1. discovery_sessions
        // ═══════════════════════════════════════════════════════════════

        if (!Schema::hasTable('discovery_sessions')) {
            Schema::create('discovery_sessions', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('created_by');

                $table->string('status', 30)->default('intake');
                // Valid statuses: intake, questioning, classifying, blueprint_ready, completed
                // Enforced by DiscoverySessionService state machine.

                $table->text('business_description');

                // Classification output
                $table->string('business_type', 50)->nullable();
                $table->decimal('classification_confidence', 5, 2)->nullable();

                // Generator metadata
                $table->string('classification_method', 30)->nullable()->default('rule_based_v1');
                $table->string('classification_version', 20)->nullable()->default('1.0.0');

                $table->timestamps();

                // ── Foreign keys ──
                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('created_by')
                      ->references('id')->on('users')
                      ->onDelete('cascade');

                // ── Indexes ──
                $table->index('workspace_id', 'idx_disc_sess_workspace');
                $table->index('created_by', 'idx_disc_sess_created_by');
                $table->index(['workspace_id', 'status'], 'idx_disc_sess_ws_status');
            });
        }

        // ═══════════════════════════════════════════════════════════════
        //  2. discovery_messages
        // ═══════════════════════════════════════════════════════════════

        if (!Schema::hasTable('discovery_messages')) {
            Schema::create('discovery_messages', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('session_id');
                $table->uuid('workspace_id');

                // 'user' or 'ai' — matches DiscoveryMessage::$fillable['role']
                $table->string('role', 10);

                $table->text('content');

                // description, follow_up_question, answer, classification, blueprint
                $table->string('message_type', 30);

                $table->jsonb('metadata')->default('{}');

                // Only created_at — model has $timestamps = false
                $table->timestamp('created_at')->useCurrent();

                // ── Foreign keys ──
                $table->foreign('session_id')
                      ->references('id')->on('discovery_sessions')
                      ->onDelete('cascade');

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                // ── Indexes ──
                $table->index('session_id', 'idx_disc_msg_session');
                $table->index('workspace_id', 'idx_disc_msg_workspace');
                $table->index(['session_id', 'message_type'], 'idx_disc_msg_sess_type');
            });
        }

        // ═══════════════════════════════════════════════════════════════
        //  3. discovery_blueprints
        // ═══════════════════════════════════════════════════════════════

        if (!Schema::hasTable('discovery_blueprints')) {
            Schema::create('discovery_blueprints', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('session_id');
                $table->uuid('workspace_id');

                $table->string('business_type', 50);
                $table->jsonb('blueprint')->default('{}');
                $table->integer('version')->default(1);

                // Generator metadata
                $table->string('generator_method', 30)->default('rule_based_v1');
                $table->string('generator_version', 20)->default('1.0.0');

                $table->timestamps();

                // ── Foreign keys ──
                $table->foreign('session_id')
                      ->references('id')->on('discovery_sessions')
                      ->onDelete('cascade');

                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                // ── Constraints ──
                // One blueprint per session (upsert pattern in DiscoverySessionService)
                $table->unique('session_id', 'uq_disc_bp_session');

                // ── Indexes ──
                $table->index('workspace_id', 'idx_disc_bp_workspace');
            });
        }

        // ═══════════════════════════════════════════════════════════════
        //  4. provisioning_runs
        // ═══════════════════════════════════════════════════════════════

        if (!Schema::hasTable('provisioning_runs')) {
            Schema::create('provisioning_runs', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('blueprint_id');

                // preview | applied | rolled_back | failed
                $table->string('status', 20)->default('preview');

                $table->jsonb('config')->default('{}');
                $table->uuid('applied_by')->nullable();
                $table->timestamp('applied_at')->nullable();
                $table->integer('version')->default(1);
                $table->jsonb('rollback_config')->nullable();
                $table->text('error_message')->nullable();

                // Model has $timestamps = false, manages created_at manually
                $table->timestamp('created_at')->nullable()->useCurrent();

                // ── Foreign keys ──
                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('blueprint_id')
                      ->references('id')->on('discovery_blueprints')
                      ->onDelete('cascade');

                $table->foreign('applied_by')
                      ->references('id')->on('users')
                      ->onDelete('set null');

                // ── Indexes ──
                $table->index('workspace_id', 'idx_prov_runs_workspace');
                $table->index('status', 'idx_prov_runs_status');
                $table->index(['workspace_id', 'status'], 'idx_prov_runs_ws_status');
            });
        }

        // ═══════════════════════════════════════════════════════════════
        //  5. workspace_configurations
        // ═══════════════════════════════════════════════════════════════

        if (!Schema::hasTable('workspace_configurations')) {
            Schema::create('workspace_configurations', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');

                $table->jsonb('enabled_modules')->default('[]');
                $table->jsonb('role_configs')->default('{}');
                $table->jsonb('pages')->default('[]');
                $table->jsonb('workflows')->default('[]');
                $table->jsonb('automations')->default('[]');
                $table->uuid('provisioning_run_id')->nullable();

                $table->timestamps();

                // ── Foreign keys ──
                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('provisioning_run_id')
                      ->references('id')->on('provisioning_runs')
                      ->onDelete('set null');

                // ── Constraints ──
                // One active configuration per workspace (updateOrCreate pattern)
                $table->unique('workspace_id', 'uq_ws_config_workspace');
            });
        }
    }

    public function down(): void
    {
        // Drop in reverse dependency order
        Schema::dropIfExists('workspace_configurations');
        Schema::dropIfExists('provisioning_runs');
        Schema::dropIfExists('discovery_blueprints');
        Schema::dropIfExists('discovery_messages');
        Schema::dropIfExists('discovery_sessions');
    }
};
