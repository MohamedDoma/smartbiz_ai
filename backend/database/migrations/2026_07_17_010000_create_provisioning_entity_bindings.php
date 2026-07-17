<?php

/**
 * Migration — Create provisioning_entity_bindings table.
 *
 * Maps Blueprint local keys → actual database entity IDs.
 * Enables idempotent re-provisioning and version updates.
 *
 * Unique constraint: (workspace_id, entity_type, local_key)
 * ensures no duplicate bindings per workspace/type/key combination.
 *
 * This migration is ONLY responsible for its own table.
 * The provisioning_runs status constraint is managed by
 * 2026_07_16_170000_provisioning_status_extension.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('provisioning_entity_bindings')) {
            Schema::create('provisioning_entity_bindings', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');

                // Entity type: location, department, team, role, warehouse, etc.
                $table->string('entity_type', 50);

                // Blueprint local key (e.g. "sales_dept", "branch_1")
                $table->string('local_key', 100);

                // Actual database entity UUID
                $table->string('entity_id', 36);

                // Provisioning metadata
                $table->uuid('last_provisioning_run_id');
                $table->uuid('last_blueprint_id');
                $table->integer('last_blueprint_version')->default(1);
                $table->jsonb('metadata')->nullable();

                $table->timestamps();

                // Foreign keys
                $table->foreign('workspace_id')
                      ->references('id')->on('workspaces')
                      ->onDelete('cascade');

                $table->foreign('last_provisioning_run_id')
                      ->references('id')->on('provisioning_runs')
                      ->onDelete('cascade');

                $table->foreign('last_blueprint_id')
                      ->references('id')->on('discovery_blueprints')
                      ->onDelete('cascade');

                // Unique binding per workspace + entity type + local key
                $table->unique(
                    ['workspace_id', 'entity_type', 'local_key'],
                    'uq_prov_binding_ws_type_key'
                );

                // Indexes
                $table->index('workspace_id', 'idx_prov_binding_workspace');
                $table->index(['workspace_id', 'entity_type'], 'idx_prov_binding_ws_type');
                $table->index('last_provisioning_run_id', 'idx_prov_binding_run');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('provisioning_entity_bindings');
    }
};
