<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Step 59.2 — AI Tool Calls audit table.
 *
 * Logs every AI tool invocation: allowed, denied, and failed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ai_tool_calls', function (Blueprint $t) {
            $t->uuid('id')->primary();
            $t->uuid('workspace_id')->nullable()->index();
            $t->uuid('user_id')->nullable()->index();
            $t->uuid('conversation_id')->nullable()->index();
            $t->uuid('message_id')->nullable();
            $t->string('tool_name', 120)->index();
            $t->string('status', 20)->default('success'); // success, denied, failed
            $t->string('required_permission', 120)->nullable();
            $t->text('denial_reason')->nullable();
            $t->jsonb('input_payload')->nullable();
            $t->jsonb('output_summary')->nullable();
            $t->integer('duration_ms')->default(0);
            $t->text('error_message')->nullable();
            $t->timestampsTz();

            $t->index('status');
            $t->index('created_at');

            $t->foreign('workspace_id')->references('id')->on('workspaces')->nullOnDelete();
            $t->foreign('user_id')->references('id')->on('users')->nullOnDelete();
            $t->foreign('conversation_id')->references('id')->on('ai_conversations')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_tool_calls');
    }
};
