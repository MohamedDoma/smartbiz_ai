<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Commission Plans ──────────────────────────────
        Schema::create('commission_plans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('plan_key')->nullable();
            $table->string('name', 255);
            $table->text('description')->nullable();
            $table->string('applies_to', 50)->default('pipeline_record');
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('applies_to');
            $table->index('is_active');
            $table->unique(['workspace_id', 'name'], 'commission_plans_ws_name_unique');
        });

        // ── B. Commission Rules ──────────────────────────────
        Schema::create('commission_rules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('commission_plan_id');
            $table->uuid('pipeline_id')->nullable();
            $table->uuid('stage_id')->nullable();
            $table->uuid('role_id')->nullable();
            $table->uuid('department_id')->nullable();
            $table->uuid('team_id')->nullable();
            $table->string('target_type', 50)->default('assigned_employee');
            $table->string('calculation_type', 50)->default('percentage');
            $table->decimal('percentage_rate', 10, 4)->nullable();
            $table->decimal('fixed_amount', 15, 2)->nullable();
            $table->string('currency', 10)->nullable()->default('LYD');
            $table->decimal('min_record_value', 15, 2)->nullable();
            $table->decimal('max_record_value', 15, 2)->nullable();
            $table->string('trigger_status', 20)->default('won');
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('commission_plan_id')->references('id')->on('commission_plans')->cascadeOnDelete();
            $table->foreign('pipeline_id')->references('id')->on('pipelines')->nullOnDelete();
            $table->foreign('stage_id')->references('id')->on('pipeline_stages')->nullOnDelete();
            $table->foreign('role_id')->references('id')->on('roles')->nullOnDelete();
            $table->foreign('department_id')->references('id')->on('departments')->nullOnDelete();
            $table->foreign('team_id')->references('id')->on('teams')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('commission_plan_id');
            $table->index('pipeline_id');
            $table->index('stage_id');
            $table->index('role_id');
            $table->index('department_id');
            $table->index('team_id');
            $table->index('is_active');
        });

        // ── C. Commission Entries ────────────────────────────
        Schema::create('commission_entries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('commission_plan_id')->nullable();
            $table->uuid('commission_rule_id')->nullable();
            $table->uuid('pipeline_record_id');
            $table->uuid('recipient_membership_id');
            $table->uuid('source_membership_id')->nullable();
            $table->decimal('base_amount', 15, 2);
            $table->decimal('commission_amount', 15, 2);
            $table->string('currency', 10)->default('LYD');
            $table->string('calculation_type', 50);
            $table->decimal('percentage_rate', 10, 4)->nullable();
            $table->decimal('fixed_amount', 15, 2)->nullable();
            $table->string('status', 20)->default('pending');
            $table->timestamp('calculated_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('commission_plan_id')->references('id')->on('commission_plans')->nullOnDelete();
            $table->foreign('commission_rule_id')->references('id')->on('commission_rules')->nullOnDelete();
            $table->foreign('pipeline_record_id')->references('id')->on('pipeline_records')->cascadeOnDelete();
            $table->foreign('recipient_membership_id')->references('id')->on('workspace_memberships')->cascadeOnDelete();
            $table->foreign('source_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_record_id');
            $table->index('recipient_membership_id');
            $table->index('status');
            $table->index('calculated_at');
            $table->unique(['commission_rule_id', 'pipeline_record_id', 'recipient_membership_id'], 'comm_entry_rule_record_recipient_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('commission_entries');
        Schema::dropIfExists('commission_rules');
        Schema::dropIfExists('commission_plans');
    }
};
