<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add assigned_membership_id to contacts for customer ownership.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('contacts', function (Blueprint $table) {
            $table->uuid('assigned_membership_id')->nullable()->after('tax_number');
            $table->foreign('assigned_membership_id')
                  ->references('id')
                  ->on('workspace_memberships')
                  ->nullOnDelete();
            $table->index('assigned_membership_id');
        });
    }

    public function down(): void
    {
        Schema::table('contacts', function (Blueprint $table) {
            $table->dropForeign(['assigned_membership_id']);
            $table->dropColumn('assigned_membership_id');
        });
    }
};
