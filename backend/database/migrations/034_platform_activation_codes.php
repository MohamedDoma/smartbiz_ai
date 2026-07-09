<?php

/**
 * Migration 034 — Platform Activation Codes & Campaigns.
 *
 * Step 58: Super Admin Integration + Activation Code / Card Generator.
 *
 * Tables created:
 *   - platform_activation_campaigns
 *   - platform_activation_codes
 *
 * We reuse the existing workspace_subscriptions / is_super_admin / workspace.status
 * rather than creating duplicate subscription tables.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Activation Campaigns ──────────────────────────
        Schema::create('platform_activation_campaigns', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('campaign_key')->nullable()->unique();
            $table->string('name');
            $table->text('description')->nullable();
            $table->string('target_market')->nullable();
            $table->string('default_plan_key')->nullable();
            $table->integer('trial_days')->nullable()->default(14);
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->string('status')->default('active');
            $table->uuid('created_by_user_id')->nullable();
            $table->timestamps();

            $table->foreign('created_by_user_id')->references('id')->on('users')->nullOnDelete();
            $table->index('status');
            $table->index('expires_at');
            $table->index('created_by_user_id');
        });

        // ── B. Activation Codes ──────────────────────────────
        Schema::create('platform_activation_codes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('campaign_id')->nullable();
            $table->string('code')->unique();
            $table->text('registration_url')->nullable();
            $table->string('default_plan_key')->nullable();
            $table->integer('trial_days')->nullable();
            $table->integer('max_uses')->default(1);
            $table->integer('used_count')->default(0);
            $table->string('status')->default('unused');
            $table->string('assigned_to_name')->nullable();
            $table->string('assigned_to_phone')->nullable();
            $table->uuid('used_by_user_id')->nullable();
            $table->uuid('used_workspace_id')->nullable();
            $table->timestamp('used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->jsonb('metadata')->nullable();
            $table->timestamps();

            $table->foreign('campaign_id')->references('id')->on('platform_activation_campaigns')->nullOnDelete();
            $table->foreign('used_by_user_id')->references('id')->on('users')->nullOnDelete();
            $table->foreign('used_workspace_id')->references('id')->on('workspaces')->nullOnDelete();
            $table->index('campaign_id');
            $table->index('status');
            $table->index('used_workspace_id');
            $table->index('used_by_user_id');
            $table->index('expires_at');
            $table->index('assigned_to_name');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('platform_activation_codes');
        Schema::dropIfExists('platform_activation_campaigns');
    }
};
