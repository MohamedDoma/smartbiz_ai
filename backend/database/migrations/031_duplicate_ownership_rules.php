<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Ownership Assignments ─────────────────────────
        Schema::create('ownership_assignments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('entity_type', 50);
            $table->uuid('entity_id');
            $table->uuid('owner_membership_id');
            $table->uuid('team_id')->nullable();
            $table->uuid('department_id')->nullable();
            $table->string('source', 30)->default('manual');
            $table->string('status', 20)->default('active');
            $table->uuid('assigned_by_membership_id')->nullable();
            $table->timestamp('assigned_at')->nullable();
            $table->timestamp('released_at')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('owner_membership_id')->references('id')->on('workspace_memberships')->cascadeOnDelete();
            $table->foreign('team_id')->references('id')->on('teams')->nullOnDelete();
            $table->foreign('department_id')->references('id')->on('departments')->nullOnDelete();
            $table->foreign('assigned_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index(['entity_type', 'entity_id']);
            $table->index('owner_membership_id');
            $table->index('team_id');
            $table->index('department_id');
            $table->index('status');
            $table->unique(['workspace_id', 'entity_type', 'entity_id'], 'ownership_ws_entity_unique');
        });

        // ── B. Ownership Transfer Logs ───────────────────────
        Schema::create('ownership_transfer_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('ownership_assignment_id')->nullable();
            $table->string('entity_type', 50);
            $table->uuid('entity_id');
            $table->uuid('from_membership_id')->nullable();
            $table->uuid('to_membership_id');
            $table->uuid('transferred_by_membership_id')->nullable();
            $table->text('reason')->nullable();
            $table->timestamp('transferred_at')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('ownership_assignment_id')->references('id')->on('ownership_assignments')->nullOnDelete();
            $table->foreign('from_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();
            $table->foreign('to_membership_id')->references('id')->on('workspace_memberships')->cascadeOnDelete();
            $table->foreign('transferred_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index(['entity_type', 'entity_id']);
            $table->index('from_membership_id');
            $table->index('to_membership_id');
            $table->index('transferred_at');
        });

        // ── C. Duplicate Rules ───────────────────────────────
        Schema::create('duplicate_rules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('rule_key')->nullable();
            $table->string('name', 255);
            $table->string('entity_type', 50);
            $table->json('match_fields');
            $table->string('match_strategy', 30)->default('normalized_exact');
            $table->string('action', 10)->default('warn');
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('entity_type');
            $table->index('is_active');
            $table->unique(['workspace_id', 'entity_type', 'name'], 'dup_rules_ws_type_name_unique');
        });

        // ── D. Duplicate Matches ─────────────────────────────
        Schema::create('duplicate_matches', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('duplicate_rule_id')->nullable();
            $table->string('entity_type', 50);
            $table->uuid('source_entity_id');
            $table->uuid('matched_entity_id');
            $table->json('match_fields')->nullable();
            $table->decimal('match_score', 5, 2)->nullable()->default(100);
            $table->string('status', 20)->default('open');
            $table->string('resolution', 30)->nullable();
            $table->uuid('resolved_by_membership_id')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('duplicate_rule_id')->references('id')->on('duplicate_rules')->nullOnDelete();
            $table->foreign('resolved_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('entity_type');
            $table->index('source_entity_id');
            $table->index('matched_entity_id');
            $table->index('status');
            $table->unique(
                ['workspace_id', 'entity_type', 'source_entity_id', 'matched_entity_id', 'duplicate_rule_id'],
                'dup_match_unique'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('duplicate_matches');
        Schema::dropIfExists('duplicate_rules');
        Schema::dropIfExists('ownership_transfer_logs');
        Schema::dropIfExists('ownership_assignments');
    }
};
