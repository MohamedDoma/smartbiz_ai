<?php

/**
 * Migration — Add metadata JSONB column to branches table.
 *
 * Supports provenance tracking: provisioning run ID, blueprint ID,
 * blueprint version, and template key stored as metadata on each branch
 * created or adopted by the provisioning engine.
 *
 * Idempotent: safe to re-run (hasColumn guard).
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('branches', 'metadata')) {
            Schema::table('branches', function (Blueprint $table) {
                $table->jsonb('metadata')->nullable()->after('phone');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('branches', 'metadata')) {
            Schema::table('branches', function (Blueprint $table) {
                $table->dropColumn('metadata');
            });
        }
    }
};
