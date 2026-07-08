<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Business Configuration Engine — Template Foundation
 *
 * Creates the template tables that allow SmartBiz to support different
 * business types (automotive, retail, workshop, restaurant, services)
 * via DB configuration instead of custom code per client.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ── 1. business_templates ─────────────────────────────
        Schema::create('business_templates', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->string('template_key')->unique();
            $table->string('name');
            $table->text('description')->nullable();
            $table->string('industry_type');
            $table->string('business_size')->nullable();
            $table->integer('version')->default(1);
            $table->boolean('is_active')->default(true);
            $table->boolean('is_default')->default(false);
            $table->integer('sort_order')->default(0);
            $table->jsonb('metadata')->nullable();
            $table->timestamps();
        });

        // ── 2. business_template_modules ──────────────────────
        Schema::create('business_template_modules', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->uuid('business_template_id');
            $table->string('module_key');
            $table->string('name');
            $table->text('description')->nullable();
            $table->boolean('is_enabled')->default(true);
            $table->boolean('is_required')->default(false);
            $table->jsonb('settings')->nullable();
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('business_template_id')
                  ->references('id')->on('business_templates')
                  ->cascadeOnDelete();

            $table->unique(['business_template_id', 'module_key']);
        });

        // ── 3. business_template_roles ────────────────────────
        Schema::create('business_template_roles', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->uuid('business_template_id');
            $table->string('role_key');
            $table->string('name');
            $table->text('description')->nullable();
            $table->integer('hierarchy_level')->default(100);
            $table->jsonb('permissions')->nullable();
            $table->boolean('is_primary_owner_role')->default(false);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('business_template_id')
                  ->references('id')->on('business_templates')
                  ->cascadeOnDelete();

            $table->unique(['business_template_id', 'role_key']);
        });

        // ── 4. business_template_workflows ────────────────────
        Schema::create('business_template_workflows', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->uuid('business_template_id');
            $table->string('workflow_type');
            $table->string('workflow_key');
            $table->string('name');
            $table->text('description')->nullable();
            $table->jsonb('config')->nullable();
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('business_template_id')
                  ->references('id')->on('business_templates')
                  ->cascadeOnDelete();

            $table->unique(['business_template_id', 'workflow_type', 'workflow_key']);
        });

        // ── 5. business_template_custom_fields ────────────────
        Schema::create('business_template_custom_fields', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->uuid('business_template_id');
            $table->string('entity_type');
            $table->string('field_key');
            $table->string('label');
            $table->string('field_type');
            $table->boolean('is_required')->default(false);
            $table->jsonb('options')->nullable();
            $table->jsonb('validation_rules')->nullable();
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('business_template_id')
                  ->references('id')->on('business_templates')
                  ->cascadeOnDelete();

            $table->unique(['business_template_id', 'entity_type', 'field_key']);
        });

        // ── 6. workspace_template_applications ────────────────
        Schema::create('workspace_template_applications', function (Blueprint $table) {
            $table->uuid('id')->primary()->default(DB::raw('gen_random_uuid()'));
            $table->uuid('workspace_id');
            $table->uuid('business_template_id');
            $table->string('template_key');
            $table->integer('template_version');
            $table->string('status')->default('applied');
            $table->timestamp('applied_at')->nullable();
            $table->uuid('applied_by_user_id')->nullable();
            $table->jsonb('snapshot')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')
                  ->references('id')->on('workspaces')
                  ->cascadeOnDelete();

            $table->foreign('business_template_id')
                  ->references('id')->on('business_templates')
                  ->restrictOnDelete();

            $table->unique(['workspace_id', 'business_template_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('workspace_template_applications');
        Schema::dropIfExists('business_template_custom_fields');
        Schema::dropIfExists('business_template_workflows');
        Schema::dropIfExists('business_template_roles');
        Schema::dropIfExists('business_template_modules');
        Schema::dropIfExists('business_templates');
    }
};
