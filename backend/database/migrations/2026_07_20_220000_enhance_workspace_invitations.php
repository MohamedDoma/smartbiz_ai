<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('workspace_invitations', function (Blueprint $table) {
            if (! Schema::hasColumn('workspace_invitations', 'token_encrypted')) {
                $table->text('token_encrypted')->nullable()->after('token_hash');
            }
            if (! Schema::hasColumn('workspace_invitations', 'department_id')) {
                $table->uuid('department_id')->nullable()->after('role_id');
                $table->foreign('department_id')->references('id')->on('departments')->nullOnDelete();
            }
            if (! Schema::hasColumn('workspace_invitations', 'team_id')) {
                $table->uuid('team_id')->nullable()->after('department_id');
                $table->foreign('team_id')->references('id')->on('teams')->nullOnDelete();
            }
            if (! Schema::hasColumn('workspace_invitations', 'job_title')) {
                $table->string('job_title', 255)->nullable()->after('team_id');
            }
            if (! Schema::hasColumn('workspace_invitations', 'preferred_locale')) {
                $table->string('preferred_locale', 5)->default('ar')->after('job_title');
            }
            if (! Schema::hasColumn('workspace_invitations', 'last_sent_at')) {
                $table->timestamp('last_sent_at')->nullable()->after('expires_at');
            }
            if (! Schema::hasColumn('workspace_invitations', 'send_count')) {
                $table->unsignedInteger('send_count')->default(0)->after('last_sent_at');
            }
            if (! Schema::hasColumn('workspace_invitations', 'delivery_status')) {
                $table->string('delivery_status', 20)->nullable()->after('send_count');
            }
            if (! Schema::hasColumn('workspace_invitations', 'delivery_error')) {
                $table->text('delivery_error')->nullable()->after('delivery_status');
            }
        });

        // Normalize legacy data before applying the case-insensitive pending
        // uniqueness rule. Existing installations may contain case variants or
        // stale pending rows that the old constraint did not handle correctly.
        DB::statement("UPDATE workspace_invitations SET email = LOWER(TRIM(email))");
        DB::statement("UPDATE workspace_invitations
            SET status = 'expired'
            WHERE status = 'pending' AND expires_at <= CURRENT_TIMESTAMP");
        DB::statement("WITH ranked AS (
                SELECT id,
                       ROW_NUMBER() OVER (
                           PARTITION BY workspace_id, LOWER(email)
                           ORDER BY created_at DESC, id DESC
                       ) AS row_number
                FROM workspace_invitations
                WHERE status = 'pending'
            )
            UPDATE workspace_invitations AS invitation
            SET status = 'revoked', revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP)
            FROM ranked
            WHERE invitation.id = ranked.id AND ranked.row_number > 1");

        // The old unique constraint blocked keeping invitation history because it
        // allowed only one row per workspace/email/status. Keep uniqueness only
        // for the currently active pending invitation.
        DB::statement('ALTER TABLE workspace_invitations DROP CONSTRAINT IF EXISTS uq_ws_email_pending');
        DB::statement('DROP INDEX IF EXISTS workspace_invitations_pending_unique');
        DB::statement("CREATE UNIQUE INDEX workspace_invitations_pending_unique
            ON workspace_invitations (workspace_id, LOWER(email))
            WHERE status = 'pending'");
        DB::statement('CREATE INDEX IF NOT EXISTS idx_workspace_invitations_department ON workspace_invitations (workspace_id, department_id)');
        DB::statement('CREATE INDEX IF NOT EXISTS idx_workspace_invitations_team ON workspace_invitations (workspace_id, team_id)');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS workspace_invitations_pending_unique');
        DB::statement('DROP INDEX IF EXISTS idx_workspace_invitations_department');
        DB::statement('DROP INDEX IF EXISTS idx_workspace_invitations_team');

        Schema::table('workspace_invitations', function (Blueprint $table) {
            foreach (['department_id', 'team_id'] as $foreign) {
                if (Schema::hasColumn('workspace_invitations', $foreign)) {
                    $table->dropForeign([$foreign]);
                }
            }

            $columns = [
                'token_encrypted',
                'department_id',
                'team_id',
                'job_title',
                'preferred_locale',
                'last_sent_at',
                'send_count',
                'delivery_status',
                'delivery_error',
            ];

            foreach ($columns as $column) {
                if (Schema::hasColumn('workspace_invitations', $column)) {
                    $table->dropColumn($column);
                }
            }
        });

        // Do not restore the legacy workspace/email/status unique constraint.
        // It prevents retaining multiple accepted, revoked, or expired invitations.
    }
};
