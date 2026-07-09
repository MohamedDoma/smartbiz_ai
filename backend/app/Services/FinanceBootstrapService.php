<?php

namespace App\Services;

use App\Models\FinanceAccount;
use App\Models\FinanceSetting;

/**
 * Creates default chart of accounts for a workspace.
 */
class FinanceBootstrapService
{
    private const DEFAULTS = [
        ['code' => '1000', 'account_key' => 'cash',          'name' => 'نقدية',             'type' => 'asset',     'normal_balance' => 'debit'],
        ['code' => '1010', 'account_key' => 'bank',          'name' => 'بنك',               'type' => 'asset',     'normal_balance' => 'debit'],
        ['code' => '1100', 'account_key' => 'receivable',    'name' => 'عملاء مدينون',       'type' => 'asset',     'normal_balance' => 'debit'],
        ['code' => '2000', 'account_key' => 'comm_payable',  'name' => 'عمولات مستحقة',      'type' => 'liability', 'normal_balance' => 'credit'],
        ['code' => '3000', 'account_key' => 'equity',        'name' => 'حقوق الملكية',       'type' => 'equity',    'normal_balance' => 'credit'],
        ['code' => '4000', 'account_key' => 'revenue',       'name' => 'إيرادات المبيعات',   'type' => 'income',    'normal_balance' => 'credit'],
        ['code' => '5000', 'account_key' => 'general_exp',   'name' => 'مصروفات عامة',       'type' => 'expense',   'normal_balance' => 'debit'],
        ['code' => '5100', 'account_key' => 'comm_expense',  'name' => 'مصروفات عمولات',     'type' => 'expense',   'normal_balance' => 'debit'],
    ];

    /**
     * Ensure all default accounts + finance settings exist for a workspace.
     */
    public function bootstrap(string $workspaceId): array
    {
        $created = 0;
        $accountIds = [];

        foreach (self::DEFAULTS as $def) {
            $acct = FinanceAccount::firstOrCreate(
                ['workspace_id' => $workspaceId, 'code' => $def['code']],
                [
                    'account_key'    => $def['account_key'],
                    'name'           => $def['name'],
                    'type'           => $def['type'],
                    'normal_balance' => $def['normal_balance'],
                    'is_system'      => true,
                    'is_active'      => true,
                    'sort_order'     => (int) $def['code'],
                ],
            );
            $accountIds[$def['account_key']] = $acct->id;
            if ($acct->wasRecentlyCreated) {
                $created++;
            }
        }

        // Create or update finance settings
        FinanceSetting::updateOrCreate(
            ['workspace_id' => $workspaceId],
            [
                'default_cash_account_id'                  => $accountIds['cash'] ?? null,
                'default_bank_account_id'                  => $accountIds['bank'] ?? null,
                'default_revenue_account_id'               => $accountIds['revenue'] ?? null,
                'default_accounts_receivable_account_id'   => $accountIds['receivable'] ?? null,
                'default_commission_expense_account_id'    => $accountIds['comm_expense'] ?? null,
                'default_commission_payable_account_id'    => $accountIds['comm_payable'] ?? null,
                'default_general_expense_account_id'       => $accountIds['general_exp'] ?? null,
            ],
        );

        return [
            'created'  => $created,
            'accounts' => FinanceAccount::where('workspace_id', $workspaceId)
                ->orderBy('sort_order')->get(),
        ];
    }
}
