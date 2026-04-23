<?php

namespace App\Services\Ai\Tools;

use App\Services\ContactService;
use App\Services\ReportingService;
use Illuminate\Support\Facades\DB;

/**
 * Read-only AI tools — call existing services, return structured data.
 * All workspace-scoped, no mutations.
 */
class ReadTools
{
    public function __construct(
        private readonly ReportingService $reporting,
        private readonly ContactService   $contacts,
    ) {}

    /**
     * Tool definitions with permission mapping.
     */
    public function definitions(): array
    {
        return [
            [
                'name'       => 'get_sales_summary',
                'permission' => 'reports.view',
                'schema'     => [
                    'name'        => 'get_sales_summary',
                    'description' => 'Get a summary of sales data including total invoices, total sales, collected, outstanding, and order stats.',
                    'parameters'  => ['type' => 'object', 'properties' => (object) [], 'required' => []],
                ],
            ],
            [
                'name'       => 'get_invoice_list',
                'permission' => 'invoices.list',
                'schema'     => [
                    'name'        => 'get_invoice_list',
                    'description' => 'List recent invoices. Optionally filter by status (paid, unpaid, partial, overdue) or by customer name.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'status'        => ['type' => 'string', 'enum' => ['paid', 'unpaid', 'partial', 'overdue']],
                            'customer_name' => ['type' => 'string', 'description' => 'Filter invoices by customer/contact name'],
                            'limit'         => ['type' => 'integer', 'description' => 'Max number of results (default 10)'],
                        ],
                        'required' => [],
                    ],
                ],
            ],
            [
                'name'       => 'get_receivables_payables',
                'permission' => 'reports.view',
                'schema'     => [
                    'name'        => 'get_receivables_payables',
                    'description' => 'Get total receivable and payable amounts.',
                    'parameters'  => ['type' => 'object', 'properties' => (object) [], 'required' => []],
                ],
            ],
            [
                'name'       => 'search_contacts',
                'permission' => 'contacts.list',
                'schema'     => [
                    'name'        => 'search_contacts',
                    'description' => 'Search for contacts/customers by name, email, phone, or type. Returns matches ranked by relevance.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'query' => ['type' => 'string', 'description' => 'Search query (name, email, phone)'],
                            'type'  => ['type' => 'string', 'enum' => ['customer', 'supplier', 'both']],
                            'limit' => ['type' => 'integer', 'description' => 'Max results (default 5)'],
                        ],
                        'required' => ['query'],
                    ],
                ],
            ],
            [
                'name'       => 'get_product_info',
                'permission' => 'products.list',
                'schema'     => [
                    'name'        => 'get_product_info',
                    'description' => 'Search for products by name or SKU. Returns product details, price, and stock level.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'query' => ['type' => 'string', 'description' => 'Product name or SKU'],
                            'limit' => ['type' => 'integer'],
                        ],
                        'required' => ['query'],
                    ],
                ],
            ],
            [
                'name'       => 'get_inventory_status',
                'permission' => 'inventory.list',
                'schema'     => [
                    'name'        => 'get_inventory_status',
                    'description' => 'Get current inventory status including total stock, low stock alerts, and product-level stock.',
                    'parameters'  => ['type' => 'object', 'properties' => (object) [], 'required' => []],
                ],
            ],
            [
                'name'       => 'get_customer_balance',
                'permission' => 'invoices.list',
                'schema'     => [
                    'name'        => 'get_customer_balance',
                    'description' => 'Get the outstanding balance for a specific customer. Searches by name and returns matches if ambiguous.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'customer_name' => ['type' => 'string', 'description' => 'Customer name to look up'],
                        ],
                        'required' => ['customer_name'],
                    ],
                ],
            ],
            [
                'name'       => 'get_account_balances',
                'permission' => 'accounts.list',
                'schema'     => [
                    'name'        => 'get_account_balances',
                    'description' => 'Get chart of accounts with balances, grouped by type.',
                    'parameters'  => ['type' => 'object', 'properties' => (object) [], 'required' => []],
                ],
            ],
        ];
    }

    /**
     * Execute a read tool.
     */
    public function execute(string $name, array $params, string $workspaceId): array
    {
        return match ($name) {
            'get_sales_summary'       => $this->reporting->salesSummary($workspaceId),
            'get_invoice_list'        => $this->getInvoiceList($workspaceId, $params),
            'get_receivables_payables'=> $this->reporting->receivablePayable($workspaceId),
            'search_contacts'         => $this->searchContacts($workspaceId, $params),
            'get_product_info'        => $this->getProductInfo($workspaceId, $params),
            'get_inventory_status'    => $this->reporting->inventorySummary($workspaceId),
            'get_customer_balance'    => $this->getCustomerBalance($workspaceId, $params),
            'get_account_balances'    => $this->reporting->accountBalances($workspaceId),
            default                   => ['error' => "Unknown read tool: {$name}"],
        };
    }

    // ── Private implementation ──────────────────────────────────

    private function getInvoiceList(string $wsId, array $params): array
    {
        $query = DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->select(['id', 'invoice_number', 'invoice_type', 'contact_id', 'net_amount', 'payment_status', 'due_date'])
            ->orderByDesc('created_at');

        if (! empty($params['status'])) {
            $query->where('payment_status', $params['status']);
        }

        if (! empty($params['customer_name'])) {
            $contactIds = DB::table('contacts')
                ->where('workspace_id', $wsId)
                ->where('name', 'ILIKE', '%' . $params['customer_name'] . '%')
                ->pluck('id');
            $query->whereIn('contact_id', $contactIds);
        }

        return $query->limit($params['limit'] ?? 10)->get()->toArray();
    }

    private function searchContacts(string $wsId, array $params): array
    {
        $q = $params['query'] ?? '';
        $query = DB::table('contacts')
            ->where('workspace_id', $wsId)
            ->where(function ($qb) use ($q) {
                $qb->where('name', 'ILIKE', "%{$q}%")
                    ->orWhere('email', 'ILIKE', "%{$q}%")
                    ->orWhere('phone', 'ILIKE', "%{$q}%");
            })
            ->select(['id', 'name', 'email', 'phone', 'type']);

        if (! empty($params['type']) && $params['type'] !== 'both') {
            $query->where('type', $params['type']);
        }

        $results = $query->limit($params['limit'] ?? 5)->get();

        // Ambiguity: flag if multiple matches found
        return [
            'matches'     => $results->toArray(),
            'match_count' => $results->count(),
            'ambiguous'   => $results->count() > 1,
        ];
    }

    private function getProductInfo(string $wsId, array $params): array
    {
        $q = $params['query'] ?? '';
        $products = DB::table('products')
            ->where('workspace_id', $wsId)
            ->where(function ($qb) use ($q) {
                $qb->where('name', 'ILIKE', "%{$q}%")
                    ->orWhere('sku', 'ILIKE', "%{$q}%");
            })
            ->select(['id', 'name', 'sku', 'base_price', 'type', 'is_deleted'])
            ->limit($params['limit'] ?? 5)
            ->get();

        return [
            'matches'     => $products->toArray(),
            'match_count' => $products->count(),
            'ambiguous'   => $products->count() > 1,
        ];
    }

    private function getCustomerBalance(string $wsId, array $params): array
    {
        $name = $params['customer_name'] ?? '';

        $contacts = DB::table('contacts')
            ->where('workspace_id', $wsId)
            ->where('name', 'ILIKE', "%{$name}%")
            ->select(['id', 'name', 'email', 'type'])
            ->limit(5)
            ->get();

        if ($contacts->isEmpty()) {
            return ['error' => 'no_match', 'message' => "No customer found matching '{$name}'."];
        }

        if ($contacts->count() > 1) {
            return [
                'ambiguous'   => true,
                'message'     => 'Multiple customers match. Please specify which one.',
                'candidates'  => $contacts->toArray(),
            ];
        }

        $contact = $contacts->first();
        $balance = DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('contact_id', $contact->id)
            ->where('invoice_type', 'sale')
            ->whereIn('payment_status', ['unpaid', 'partial'])
            ->selectRaw('COUNT(*) as invoice_count, COALESCE(SUM(net_amount),0) as total_outstanding')
            ->first();

        return [
            'customer'          => $contact,
            'outstanding_count' => (int) $balance->invoice_count,
            'outstanding_total' => (float) $balance->total_outstanding,
        ];
    }
}
