<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Migration 025 — workspace_invitations table.
 *
 * Stores invite records for employees to join workspaces.
 * Token is hashed (SHA-256); raw token is never persisted.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('workspace_invitations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('email', 255);
            $table->string('full_name', 255)->nullable();
            $table->uuid('role_id')->nullable();
            $table->uuid('invited_by_user_id');
            $table->uuid('accepted_user_id')->nullable();
            $table->string('token_hash', 64)->unique();
            $table->string('status', 20)->default('pending');
            $table->timestamp('expires_at');
            $table->timestamp('accepted_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->jsonb('metadata')->nullable();
            $table->timestamps();

            // Foreign keys
            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('role_id')->references('id')->on('roles')->nullOnDelete();
            $table->foreign('invited_by_user_id')->references('id')->on('users')->cascadeOnDelete();
            $table->foreign('accepted_user_id')->references('id')->on('users')->nullOnDelete();

            // Indexes
            $table->index('workspace_id');
            $table->index('email');
            $table->index('status');
            $table->index('expires_at');

            // Prevent duplicate pending invites for same workspace+email
            $table->unique(['workspace_id', 'email', 'status'], 'uq_ws_email_pending');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('workspace_invitations');
    }
};
