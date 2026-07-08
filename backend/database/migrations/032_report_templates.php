<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Report Templates ──────────────────────────────
        Schema::create('report_templates', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('template_key')->nullable();
            $table->string('name', 255);
            $table->text('description')->nullable();
            $table->string('data_source', 50);
            $table->json('columns');
            $table->json('filters')->nullable();
            $table->json('group_by')->nullable();
            $table->json('sort_by')->nullable();
            $table->string('visibility', 20)->default('workspace');
            $table->uuid('created_by_membership_id')->nullable();
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('created_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('data_source');
            $table->index('visibility');
            $table->index('created_by_membership_id');
            $table->index('is_active');
            $table->unique(['workspace_id', 'name'], 'report_tpl_ws_name_unique');
        });

        // ── B. Report Runs ───────────────────────────────────
        Schema::create('report_runs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('report_template_id')->nullable();
            $table->string('data_source', 50);
            $table->uuid('run_by_membership_id')->nullable();
            $table->string('status', 20)->default('completed');
            $table->json('parameters')->nullable();
            $table->json('result_summary')->nullable();
            $table->integer('row_count')->default(0);
            $table->text('error_message')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('report_template_id')->references('id')->on('report_templates')->nullOnDelete();
            $table->foreign('run_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('report_template_id');
            $table->index('data_source');
            $table->index('run_by_membership_id');
            $table->index('status');
            $table->index('started_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('report_runs');
        Schema::dropIfExists('report_templates');
    }
};
