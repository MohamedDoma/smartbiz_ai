<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Pipelines ─────────────────────────────────────
        Schema::create('pipelines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('pipeline_key')->nullable();
            $table->string('name', 255);
            $table->text('description')->nullable();
            $table->string('entity_type', 50)->default('generic');
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('entity_type');
            $table->index('is_active');
            $table->unique(['workspace_id', 'name']);
        });

        // ── B. Pipeline Stages ───────────────────────────────
        Schema::create('pipeline_stages', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('pipeline_id');
            $table->string('stage_key')->nullable();
            $table->string('name', 255);
            $table->text('description')->nullable();
            $table->string('status_type', 20)->default('open');
            $table->integer('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('pipeline_id')->references('id')->on('pipelines')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_id');
            $table->index('is_active');
            $table->unique(['pipeline_id', 'name']);
        });

        // ── C. Pipeline Records ──────────────────────────────
        Schema::create('pipeline_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('pipeline_id');
            $table->uuid('stage_id');
            $table->string('title', 255);
            $table->text('description')->nullable();
            $table->uuid('contact_id')->nullable();
            $table->uuid('assigned_membership_id')->nullable();
            $table->decimal('value_amount', 15, 2)->nullable();
            $table->string('currency', 10)->nullable();
            $table->string('status', 20)->default('open');
            $table->date('expected_close_date')->nullable();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('pipeline_id')->references('id')->on('pipelines')->cascadeOnDelete();
            $table->foreign('stage_id')->references('id')->on('pipeline_stages')->cascadeOnDelete();
            $table->foreign('contact_id')->references('id')->on('contacts')->nullOnDelete();
            $table->foreign('assigned_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_id');
            $table->index('stage_id');
            $table->index('assigned_membership_id');
            $table->index('status');
        });

        // ── D. Custom Fields ─────────────────────────────────
        Schema::create('custom_fields', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('pipeline_id')->nullable();
            $table->string('field_key')->nullable();
            $table->string('label', 255);
            $table->string('field_type', 30);
            $table->json('options')->nullable();
            $table->boolean('is_required')->default(false);
            $table->string('applies_to', 50)->default('pipeline_record');
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('pipeline_id')->references('id')->on('pipelines')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_id');
            $table->index('applies_to');
            $table->index('is_active');
        });

        // ── E. Custom Field Values ───────────────────────────
        Schema::create('custom_field_values', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('custom_field_id');
            $table->string('record_type', 50)->default('pipeline_record');
            $table->uuid('record_id');
            $table->text('value_text')->nullable();
            $table->decimal('value_number', 18, 4)->nullable();
            $table->boolean('value_boolean')->nullable();
            $table->date('value_date')->nullable();
            $table->json('value_json')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('custom_field_id')->references('id')->on('custom_fields')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('custom_field_id');
            $table->index(['record_type', 'record_id']);
            $table->unique(['custom_field_id', 'record_type', 'record_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('custom_field_values');
        Schema::dropIfExists('custom_fields');
        Schema::dropIfExists('pipeline_records');
        Schema::dropIfExists('pipeline_stages');
        Schema::dropIfExists('pipelines');
    }
};
