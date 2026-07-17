<?php

/**
 * Migration 039 — Add discovery_state JSONB to discovery_sessions
 *
 * Adds a persistent JSONB field to track the structured state of the
 * adaptive AI discovery conversation. Stores extracted facts, missing
 * information, completeness, and conversation metadata.
 *
 * Also adds 'ready' to the discovery_messages message_type check constraint.
 *
 * References:
 *  - app/Models/DiscoverySession.php
 *  - app/Services/DiscoverySessionService.php
 *  - app/Services/Discovery/DiscoveryInformationCatalog.php
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('discovery_sessions') && !Schema::hasColumn('discovery_sessions', 'discovery_state')) {
            Schema::table('discovery_sessions', function (Blueprint $table) {
                $table->jsonb('discovery_state')->nullable()->after('classification_version');
            });
        }

        // Add 'ready' to the message_type CHECK constraint
        DB::statement("ALTER TABLE discovery_messages DROP CONSTRAINT IF EXISTS discovery_messages_message_type_check");
        DB::statement("ALTER TABLE discovery_messages ADD CONSTRAINT discovery_messages_message_type_check CHECK (message_type IN ('description', 'follow_up_question', 'answer', 'classification', 'blueprint', 'ready'))");
    }

    public function down(): void
    {
        // Revert message_type constraint
        DB::statement("ALTER TABLE discovery_messages DROP CONSTRAINT IF EXISTS discovery_messages_message_type_check");
        DB::statement("ALTER TABLE discovery_messages ADD CONSTRAINT discovery_messages_message_type_check CHECK (message_type IN ('description', 'follow_up_question', 'answer', 'classification', 'blueprint'))");

        if (Schema::hasColumn('discovery_sessions', 'discovery_state')) {
            Schema::table('discovery_sessions', function (Blueprint $table) {
                $table->dropColumn('discovery_state');
            });
        }
    }
};
