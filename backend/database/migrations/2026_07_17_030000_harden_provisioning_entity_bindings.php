<?php

/**
 * Migration — Harden provisioning_entity_bindings.
 *
 * Adds:
 *   - ownership_type: tracks how the binding was created
 *     ('created_by_provisioning' | 'adopted_template_entity' | 'created_by_template')
 *   - unique constraint on (workspace_id, entity_type, entity_id)
 *     prevents two local keys from binding to the same entity
 *   - makes last_provisioning_run_id and last_blueprint_id nullable
 *     for template-created bindings that don't go through a provisioning run
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('provisioning_entity_bindings')) {
            return;
        }

        Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
            // Ownership type: how this binding came into existence
            if (!Schema::hasColumn('provisioning_entity_bindings', 'ownership_type')) {
                $table->string('ownership_type', 30)
                      ->default('created_by_provisioning')
                      ->after('entity_id');
            }
        });

        // Make run_id/blueprint_id nullable for template-sourced bindings
        if (Schema::hasColumn('provisioning_entity_bindings', 'last_provisioning_run_id')) {
            Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
                $table->uuid('last_provisioning_run_id')->nullable()->change();
            });
        }

        if (Schema::hasColumn('provisioning_entity_bindings', 'last_blueprint_id')) {
            Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
                $table->uuid('last_blueprint_id')->nullable()->change();
            });
        }

        // Add unique constraint: no two local keys can bind to the same entity
        $indexExists = collect(\DB::select(
            "SELECT indexname FROM pg_indexes WHERE tablename = 'provisioning_entity_bindings' AND indexname = 'uq_prov_binding_ws_type_entity'"
        ))->isNotEmpty();

        if (!$indexExists) {
            Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
                $table->unique(
                    ['workspace_id', 'entity_type', 'entity_id'],
                    'uq_prov_binding_ws_type_entity'
                );
            });
        }
    }

    public function down(): void
    {
        if (!Schema::hasTable('provisioning_entity_bindings')) {
            return;
        }

        $indexExists = collect(\DB::select(
            "SELECT indexname FROM pg_indexes WHERE tablename = 'provisioning_entity_bindings' AND indexname = 'uq_prov_binding_ws_type_entity'"
        ))->isNotEmpty();

        if ($indexExists) {
            Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
                $table->dropUnique('uq_prov_binding_ws_type_entity');
            });
        }

        if (Schema::hasColumn('provisioning_entity_bindings', 'ownership_type')) {
            Schema::table('provisioning_entity_bindings', function (Blueprint $table) {
                $table->dropColumn('ownership_type');
            });
        }
    }
};
