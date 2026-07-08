<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Migration 026 — Role & permission management enhancements.
 *
 * A. workspace_invitation_roles — multi-role invites.
 * B. roles table — add is_active, sort_order if missing.
 */
return new class extends Migration
{
    public function up(): void
    {
        // A. Multi-role invite support
        Schema::create('workspace_invitation_roles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_invitation_id');
            $table->uuid('role_id');
            $table->boolean('is_primary')->default(false);
            $table->timestamps();

            $table->foreign('workspace_invitation_id')
                  ->references('id')->on('workspace_invitations')
                  ->cascadeOnDelete();
            $table->foreign('role_id')
                  ->references('id')->on('roles')
                  ->cascadeOnDelete();

            $table->index('workspace_invitation_id');
            $table->index('role_id');
            $table->unique(['workspace_invitation_id', 'role_id'], 'uq_inv_role');
        });

        // B. Roles table additions (safe — nullable/defaults only)
        if (! Schema::hasColumn('roles', 'is_active')) {
            Schema::table('roles', function (Blueprint $table) {
                $table->boolean('is_active')->default(true)->after('is_deletable');
            });
        }
        if (! Schema::hasColumn('roles', 'sort_order')) {
            Schema::table('roles', function (Blueprint $table) {
                $table->integer('sort_order')->default(0)->after('is_active');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('workspace_invitation_roles');

        if (Schema::hasColumn('roles', 'is_active')) {
            Schema::table('roles', function (Blueprint $table) {
                $table->dropColumn('is_active');
            });
        }
        if (Schema::hasColumn('roles', 'sort_order')) {
            Schema::table('roles', function (Blueprint $table) {
                $table->dropColumn('sort_order');
            });
        }
    }
};
