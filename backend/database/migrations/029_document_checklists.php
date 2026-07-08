<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Document Checklists ───────────────────────────
        Schema::create('document_checklists', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('pipeline_id')->nullable();
            $table->uuid('stage_id')->nullable();
            $table->string('checklist_key')->nullable();
            $table->string('name', 255);
            $table->text('description')->nullable();
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('pipeline_id')->references('id')->on('pipelines')->nullOnDelete();
            $table->foreign('stage_id')->references('id')->on('pipeline_stages')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_id');
            $table->index('stage_id');
            $table->index('is_active');
            $table->unique(['workspace_id', 'pipeline_id', 'stage_id', 'name'], 'doc_checklists_ws_pip_stage_name_unique');
        });

        // ── B. Document Checklist Items ──────────────────────
        Schema::create('document_checklist_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('document_checklist_id');
            $table->string('item_key')->nullable();
            $table->string('title', 255);
            $table->text('description')->nullable();
            $table->boolean('is_required')->default(true);
            $table->json('accepted_file_types')->nullable();
            $table->integer('max_file_size_mb')->nullable()->default(10);
            $table->integer('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('document_checklist_id')->references('id')->on('document_checklists')->cascadeOnDelete();

            $table->index('workspace_id');
            $table->index('document_checklist_id');
            $table->index('is_required');
            $table->index('is_active');
            $table->unique(['document_checklist_id', 'title'], 'doc_items_checklist_title_unique');
        });

        // ── C. Record Documents ──────────────────────────────
        Schema::create('record_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('pipeline_record_id');
            $table->uuid('document_checklist_item_id')->nullable();
            $table->string('title', 255);
            $table->string('status', 20)->default('uploaded');
            $table->string('file_path')->nullable();
            $table->string('original_filename')->nullable();
            $table->string('mime_type', 100)->nullable();
            $table->unsignedInteger('file_size')->nullable();
            $table->string('external_reference')->nullable();
            $table->text('notes')->nullable();
            $table->uuid('uploaded_by_membership_id')->nullable();
            $table->timestamp('uploaded_at')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('pipeline_record_id')->references('id')->on('pipeline_records')->cascadeOnDelete();
            $table->foreign('document_checklist_item_id')->references('id')->on('document_checklist_items')->nullOnDelete();
            $table->foreign('uploaded_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

            $table->index('workspace_id');
            $table->index('pipeline_record_id');
            $table->index('document_checklist_item_id');
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('record_documents');
        Schema::dropIfExists('document_checklist_items');
        Schema::dropIfExists('document_checklists');
    }
};
