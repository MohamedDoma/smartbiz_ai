<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ── A. Finance Accounts (Chart of Accounts) ──────
        Schema::create('finance_accounts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('account_key', 50)->nullable();
            $table->string('code', 20)->nullable();
            $table->string('name', 255);
            $table->string('type', 20); // asset, liability, equity, income, expense
            $table->string('normal_balance', 10); // debit, credit
            $table->boolean('is_system')->default(false);
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->index('workspace_id');
            $table->index('type');
            $table->index('is_active');
            $table->index('is_system');
            $table->unique(['workspace_id', 'code'], 'fin_acct_ws_code_unique');
        });

        // ── B. Finance Transactions ──────────────────────
        Schema::create('finance_transactions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->string('transaction_number', 50)->nullable();
            $table->date('transaction_date');
            $table->text('description')->nullable();
            $table->string('source_type', 50)->nullable();
            $table->uuid('source_id')->nullable();
            $table->string('status', 20)->default('posted');
            $table->string('currency', 10)->default('LYD');
            $table->decimal('total_debit', 15, 2)->default(0);
            $table->decimal('total_credit', 15, 2)->default(0);
            $table->uuid('posted_by_membership_id')->nullable();
            $table->timestamp('posted_at')->nullable();
            $table->timestamp('voided_at')->nullable();
            $table->json('metadata')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('posted_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();
            $table->index('workspace_id');
            $table->index('transaction_date');
            $table->index(['source_type', 'source_id']);
            $table->index('status');
            $table->index('posted_by_membership_id');
        });

        // ── C. Finance Transaction Lines ─────────────────
        Schema::create('finance_transaction_lines', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->uuid('finance_transaction_id');
            $table->uuid('finance_account_id');
            $table->text('description')->nullable();
            $table->decimal('debit_amount', 15, 2)->default(0);
            $table->decimal('credit_amount', 15, 2)->default(0);
            $table->string('currency', 10)->default('LYD');
            $table->integer('line_order')->default(0);
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('finance_transaction_id')->references('id')->on('finance_transactions')->cascadeOnDelete();
            $table->foreign('finance_account_id')->references('id')->on('finance_accounts')->restrictOnDelete();
            $table->index('workspace_id');
            $table->index('finance_transaction_id');
            $table->index('finance_account_id');
        });

        // ── D. Finance Expenses ──────────────────────────
        Schema::create('finance_expenses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id');
            $table->date('expense_date');
            $table->string('category', 100)->nullable();
            $table->text('description');
            $table->decimal('amount', 15, 2);
            $table->string('currency', 10)->default('LYD');
            $table->string('payment_method', 30)->nullable();
            $table->uuid('paid_by_membership_id')->nullable();
            $table->uuid('finance_transaction_id')->nullable();
            $table->string('status', 20)->default('posted');
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
            $table->foreign('paid_by_membership_id')->references('id')->on('workspace_memberships')->nullOnDelete();
            $table->foreign('finance_transaction_id')->references('id')->on('finance_transactions')->nullOnDelete();
            $table->index('workspace_id');
            $table->index('expense_date');
            $table->index('category');
            $table->index('status');
            $table->index('finance_transaction_id');
        });

        // ── E. Finance Settings ──────────────────────────
        Schema::create('finance_settings', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('workspace_id')->unique();
            $table->uuid('default_cash_account_id')->nullable();
            $table->uuid('default_bank_account_id')->nullable();
            $table->uuid('default_revenue_account_id')->nullable();
            $table->uuid('default_accounts_receivable_account_id')->nullable();
            $table->uuid('default_commission_expense_account_id')->nullable();
            $table->uuid('default_commission_payable_account_id')->nullable();
            $table->uuid('default_general_expense_account_id')->nullable();
            $table->timestamps();

            $table->foreign('workspace_id')->references('id')->on('workspaces')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('finance_settings');
        Schema::dropIfExists('finance_expenses');
        Schema::dropIfExists('finance_transaction_lines');
        Schema::dropIfExists('finance_transactions');
        Schema::dropIfExists('finance_accounts');
    }
};
