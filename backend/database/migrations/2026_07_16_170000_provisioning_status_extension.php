<?php

/**
 * Migration — Extend provisioning_runs status vocabulary.
 *
 * Adds a CHECK constraint for the full status vocabulary:
 *   preview, prepared, processing, foundation_applied, applied, rolled_back, failed
 *
 * Migration 038 created the table without a CHECK constraint (plain string column).
 * This migration adds it as a safety net.
 *
 * Idempotent: uses DROP … IF EXISTS before CREATE.
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('provisioning_runs')) {
            DB::statement('ALTER TABLE provisioning_runs DROP CONSTRAINT IF EXISTS provisioning_runs_status_check');
            DB::statement(
                "ALTER TABLE provisioning_runs ADD CONSTRAINT provisioning_runs_status_check "
                . "CHECK (status IN ('preview','prepared','processing','foundation_applied','applied','rolled_back','failed'))"
            );
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('provisioning_runs')) {
            DB::statement('ALTER TABLE provisioning_runs DROP CONSTRAINT IF EXISTS provisioning_runs_status_check');
        }
    }
};
