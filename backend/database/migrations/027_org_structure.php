<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── Departments: add missing columns ──────────────────
        if (Schema::hasTable('departments')) {
            Schema::table('departments', function (Blueprint $table) {
                if (! Schema::hasColumn('departments', 'department_key')) {
                    $table->string('department_key')->nullable()->after('workspace_id');
                }
                if (! Schema::hasColumn('departments', 'manager_membership_id')) {
                    $table->uuid('manager_membership_id')->nullable()->after('manager_id');
                    $table->foreign('manager_membership_id')
                          ->references('id')->on('workspace_memberships')
                          ->nullOnDelete();
                }
                if (! Schema::hasColumn('departments', 'is_active')) {
                    $table->boolean('is_active')->default(true)->after('description');
                }
                if (! Schema::hasColumn('departments', 'sort_order')) {
                    $table->integer('sort_order')->default(0)->after('is_active');
                }
            });

            // Add unique index if missing
            try {
                Schema::table('departments', function (Blueprint $table) {
                    $table->unique(['workspace_id', 'name'], 'departments_ws_name_unique');
                });
            } catch (\Throwable $e) {
                // Index already exists — skip
            }
        }

        // ── Teams table ──────────────────────────────────────
        if (! Schema::hasTable('teams')) {
            Schema::create('teams', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->uuid('workspace_id');
                $table->uuid('department_id')->nullable();
                $table->string('team_key')->nullable();
                $table->string('name');
                $table->text('description')->nullable();
                $table->uuid('manager_membership_id')->nullable();
                $table->boolean('is_active')->default(true);
                $table->integer('sort_order')->default(0);
                $table->timestamps();

                $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
                $table->foreign('department_id')->references('id')->on('departments')->nullOnDelete();
                $table->foreign('manager_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();

                $table->index('workspace_id');
                $table->index('department_id');
                $table->index('is_active');
                $table->unique(['workspace_id', 'name'], 'teams_ws_name_unique');
            });
        }

        // ── workspace_memberships: add missing columns ───────
        Schema::table('workspace_memberships', function (Blueprint $table) {
            if (! Schema::hasColumn('workspace_memberships', 'team_id')) {
                $table->uuid('team_id')->nullable()->after('department_id');
                $table->foreign('team_id')->references('id')->on('teams')->nullOnDelete();
            }
            if (! Schema::hasColumn('workspace_memberships', 'job_title')) {
                $table->string('job_title')->nullable()->after('team_id');
            }
        });
    }

    public function down(): void
    {
        Schema::table('workspace_memberships', function (Blueprint $table) {
            if (Schema::hasColumn('workspace_memberships', 'team_id')) {
                $table->dropForeign(['team_id']);
                $table->dropColumn('team_id');
            }
            if (Schema::hasColumn('workspace_memberships', 'job_title')) {
                $table->dropColumn('job_title');
            }
        });

        Schema::dropIfExists('teams');

        if (Schema::hasTable('departments')) {
            Schema::table('departments', function (Blueprint $table) {
                foreach (['department_key', 'is_active', 'sort_order'] as $col) {
                    if (Schema::hasColumn('departments', $col)) {
                        $table->dropColumn($col);
                    }
                }
                if (Schema::hasColumn('departments', 'manager_membership_id')) {
                    $table->dropForeign(['manager_membership_id']);
                    $table->dropColumn('manager_membership_id');
                }
            });
        }
    }
};
