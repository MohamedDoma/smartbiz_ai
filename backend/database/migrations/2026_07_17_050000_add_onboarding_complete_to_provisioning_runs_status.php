<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Task 1.6D — Expand provisioning_runs.status CHECK constraint.
 *
 * Adds 'onboarding_complete' to the allowed status values.
 * Idempotent: detects the current constraint definition before acting.
 */
return new class extends Migration
{
    private const CONSTRAINT_NAME = 'provisioning_runs_status_check';

    private const ALLOWED_STATUSES = [
        'preview',
        'prepared',
        'processing',
        'foundation_applied',
        'applied',
        'onboarding_complete',
        'rolled_back',
        'failed',
    ];

    public function up(): void
    {
        // Check whether the constraint already includes onboarding_complete
        $existing = DB::selectOne("
            SELECT pg_get_constraintdef(oid) AS def
            FROM pg_constraint
            WHERE conrelid = 'provisioning_runs'::regclass
              AND conname  = ?
        ", [self::CONSTRAINT_NAME]);

        if ($existing && str_contains($existing->def, 'onboarding_complete')) {
            // Already expanded — idempotent no-op
            return;
        }

        // Build the new CHECK expression
        $values = collect(self::ALLOWED_STATUSES)
            ->map(fn (string $s) => "'{$s}'::character varying")
            ->implode(', ');

        DB::statement('ALTER TABLE provisioning_runs DROP CONSTRAINT IF EXISTS ' . self::CONSTRAINT_NAME);
        DB::statement("
            ALTER TABLE provisioning_runs
            ADD CONSTRAINT " . self::CONSTRAINT_NAME . "
            CHECK ((status)::text = ANY (ARRAY[{$values}]::text[]))
        ");
    }

    public function down(): void
    {
        // Restore original constraint without onboarding_complete
        $original = collect(self::ALLOWED_STATUSES)
            ->reject(fn (string $s) => $s === 'onboarding_complete')
            ->map(fn (string $s) => "'{$s}'::character varying")
            ->implode(', ');

        DB::statement('ALTER TABLE provisioning_runs DROP CONSTRAINT IF EXISTS ' . self::CONSTRAINT_NAME);
        DB::statement("
            ALTER TABLE provisioning_runs
            ADD CONSTRAINT " . self::CONSTRAINT_NAME . "
            CHECK ((status)::text = ANY (ARRAY[{$original}]::text[]))
        ");
    }
};
