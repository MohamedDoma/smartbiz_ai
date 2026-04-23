<?php

namespace App\Services\Ai\Tools;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Action AI tools — create draft proposals that require user confirmation.
 * Never execute directly; creates ai_change_requests records.
 */
class ActionTools
{
    public function definitions(): array
    {
        return [
            [
                'name'       => 'draft_invoice',
                'permission' => 'invoices.create',
                'schema'     => [
                    'name'        => 'draft_invoice',
                    'description' => 'Draft a new invoice. This will NOT be created immediately — the user must confirm first. Provide customer name and line items.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'customer_name' => ['type' => 'string', 'description' => 'Customer/contact name'],
                            'invoice_type'  => ['type' => 'string', 'enum' => ['sale', 'purchase'], 'description' => 'Defaults to sale'],
                            'items'         => [
                                'type'  => 'array',
                                'items' => [
                                    'type'       => 'object',
                                    'properties' => [
                                        'product_name' => ['type' => 'string'],
                                        'quantity'     => ['type' => 'number'],
                                        'unit_price'   => ['type' => 'number'],
                                    ],
                                    'required' => ['product_name', 'quantity'],
                                ],
                            ],
                            'notes' => ['type' => 'string'],
                        ],
                        'required' => ['customer_name', 'items'],
                    ],
                ],
            ],
            [
                'name'       => 'draft_contact',
                'permission' => 'contacts.create',
                'schema'     => [
                    'name'        => 'draft_contact',
                    'description' => 'Draft a new contact/customer. Requires confirmation before creation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'name'    => ['type' => 'string'],
                            'email'   => ['type' => 'string'],
                            'phone'   => ['type' => 'string'],
                            'type'    => ['type' => 'string', 'enum' => ['customer', 'supplier', 'both']],
                            'address' => ['type' => 'string'],
                        ],
                        'required' => ['name', 'type'],
                    ],
                ],
            ],
            [
                'name'       => 'draft_product',
                'permission' => 'products.create',
                'schema'     => [
                    'name'        => 'draft_product',
                    'description' => 'Draft a new product. Requires confirmation before creation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'name'       => ['type' => 'string'],
                            'sku'        => ['type' => 'string'],
                            'unit_price' => ['type' => 'number'],
                            'type'       => ['type' => 'string', 'enum' => ['goods', 'service']],
                        ],
                        'required' => ['name'],
                    ],
                ],
            ],
            [
                'name'       => 'draft_order',
                'permission' => 'orders.create',
                'schema'     => [
                    'name'        => 'draft_order',
                    'description' => 'Draft a new sale or purchase order. Requires confirmation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'customer_name' => ['type' => 'string', 'description' => 'Customer/contact name'],
                            'order_type'    => ['type' => 'string', 'enum' => ['sale_order', 'purchase_order']],
                            'items'         => [
                                'type'  => 'array',
                                'items' => [
                                    'type'       => 'object',
                                    'properties' => [
                                        'product_name' => ['type' => 'string'],
                                        'quantity'     => ['type' => 'number'],
                                        'unit_price'   => ['type' => 'number'],
                                    ],
                                    'required' => ['product_name', 'quantity'],
                                ],
                            ],
                            'notes' => ['type' => 'string'],
                        ],
                        'required' => ['customer_name', 'order_type', 'items'],
                    ],
                ],
            ],
            [
                'name'       => 'draft_payment',
                'permission' => 'payments.create',
                'schema'     => [
                    'name'        => 'draft_payment',
                    'description' => 'Draft a payment against an invoice. Requires confirmation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'invoice_number' => ['type' => 'string', 'description' => 'Invoice number or identifier'],
                            'amount'         => ['type' => 'number', 'description' => 'Payment amount'],
                            'payment_method' => ['type' => 'string', 'enum' => ['cash', 'bank_transfer', 'card', 'check']],
                        ],
                        'required' => ['invoice_number', 'amount', 'payment_method'],
                    ],
                ],
            ],
            [
                'name'       => 'draft_inventory_adjustment',
                'permission' => 'inventory.manage',
                'schema'     => [
                    'name'        => 'draft_inventory_adjustment',
                    'description' => 'Draft a stock adjustment for a product in a warehouse. Requires confirmation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'product_name'    => ['type' => 'string'],
                            'warehouse_name'  => ['type' => 'string', 'description' => 'Optional. Uses first warehouse if omitted.'],
                            'quantity_change'  => ['type' => 'number', 'description' => 'Positive to add, negative to remove'],
                            'reason'          => ['type' => 'string'],
                        ],
                        'required' => ['product_name', 'quantity_change'],
                    ],
                ],
            ],
            [
                'name'       => 'update_invoice_status',
                'permission' => 'invoices.update',
                'schema'     => [
                    'name'        => 'update_invoice_status',
                    'description' => 'Update an invoice payment status. Requires confirmation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'invoice_number' => ['type' => 'string'],
                            'new_status'     => ['type' => 'string', 'enum' => ['paid', 'partial', 'unpaid', 'overdue', 'void']],
                        ],
                        'required' => ['invoice_number', 'new_status'],
                    ],
                ],
            ],
            [
                'name'       => 'update_order_status',
                'permission' => 'orders.update',
                'schema'     => [
                    'name'        => 'update_order_status',
                    'description' => 'Update an order status. Requires confirmation.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'order_number' => ['type' => 'string'],
                            'new_status'   => ['type' => 'string', 'enum' => ['draft', 'confirmed', 'in_progress', 'completed', 'cancelled']],
                        ],
                        'required' => ['order_number', 'new_status'],
                    ],
                ],
            ],
            [
                'name'       => 'send_email',
                'permission' => 'contacts.read',
                'schema'     => [
                    'name'        => 'send_email',
                    'description' => 'Send an email to a known contact or workspace user. Must go through confirmation. Recipient must exist in contacts or workspace members.',
                    'parameters'  => [
                        'type'       => 'object',
                        'properties' => [
                            'recipient_name' => ['type' => 'string', 'description' => 'Name of the contact or user to email'],
                            'subject'        => ['type' => 'string', 'description' => 'Email subject line'],
                            'body'           => ['type' => 'string', 'description' => 'Email body content (plain text)'],
                        ],
                        'required' => ['recipient_name', 'subject', 'body'],
                    ],
                ],
            ],
        ];
    }

    /**
     * Execute an action tool — creates a draft (never executes directly).
     */
    public function execute(string $name, array $params, string $workspaceId, string $userId, ?string $conversationId): array
    {
         // Resolve ambiguity for customer_name in draft_invoice or draft_order
        if (in_array($name, ['draft_invoice', 'draft_order']) && ! empty($params['customer_name'])) {
            $resolve = $this->resolveContact($workspaceId, $params['customer_name']);
            if (! empty($resolve['ambiguous'])) {
                return [
                    'action'      => 'ambiguity_resolution',
                    'message'     => 'Multiple customers match "' . $params['customer_name'] . '". Please specify which one.',
                    'candidates'  => $resolve['candidates'],
                ];
            }
            if (! empty($resolve['error'])) {
                return $resolve;
            }
            $params['resolved_contact_id']   = $resolve['contact']->id;
            $params['resolved_contact_name'] = $resolve['contact']->name;
        }

        // Resolve ambiguity for product names in items (invoice or order)
        if (in_array($name, ['draft_invoice', 'draft_order']) && ! empty($params['items'])) {
            foreach ($params['items'] as $i => $item) {
                $resolve = $this->resolveProduct($workspaceId, $item['product_name'] ?? '');
                if (! empty($resolve['ambiguous'])) {
                    return [
                        'action'     => 'ambiguity_resolution',
                        'message'    => 'Multiple products match "' . ($item['product_name'] ?? '') . '". Please specify which one.',
                        'candidates' => $resolve['candidates'],
                        'item_index' => $i,
                    ];
                }
                if (! empty($resolve['match'])) {
                    $params['items'][$i]['resolved_product_id']   = $resolve['match']->id;
                    $params['items'][$i]['resolved_product_name'] = $resolve['match']->name;
                    $params['items'][$i]['unit_price']            = $item['unit_price'] ?? (float) $resolve['match']->base_price;
                }
            }
        }

        // Resolve product for inventory adjustment
        if ($name === 'draft_inventory_adjustment' && ! empty($params['product_name'])) {
            $resolve = $this->resolveProduct($workspaceId, $params['product_name']);
            if (! empty($resolve['ambiguous'])) {
                return [
                    'action'     => 'ambiguity_resolution',
                    'message'    => 'Multiple products match "' . $params['product_name'] . '". Please specify which one.',
                    'candidates' => $resolve['candidates'],
                ];
            }
            if (! empty($resolve['match'])) {
                $params['resolved_product_id']   = $resolve['match']->id;
                $params['resolved_product_name'] = $resolve['match']->name;
            }
        }

        // Duplicate detection for draft_contact
        if ($name === 'draft_contact' && ! empty($params['name'])) {
            $existing = DB::table('contacts')
                ->where('workspace_id', $workspaceId)
                ->where('name', 'ILIKE', '%' . $params['name'] . '%')
                ->select(['id', 'name', 'email', 'phone', 'type'])
                ->limit(3)
                ->get();
            if ($existing->count() > 0) {
                return [
                    'action'    => 'ambiguity_resolution',
                    'message'   => 'Similar contacts already exist. Confirm this is a new contact.',
                    'existing'  => $existing->toArray(),
                    'draft'     => $params,
                    'requires_confirmation' => true,
                ];
            }
        }

        // Create pending action in ai_change_requests
        $actionId = Str::uuid()->toString();
        $changeType = match ($name) {
            'draft_invoice'              => 'settings',
            'draft_contact'              => 'settings',
            'draft_product'              => 'settings',
            'draft_order'                => 'order',
            'draft_payment'              => 'payment',
            'draft_inventory_adjustment' => 'inventory',
            'update_invoice_status'      => 'status_update',
            'update_order_status'        => 'status_update',
            'send_email'                 => 'email',
            default                      => 'settings',
        };
        $riskLevel = match ($name) {
            'draft_payment', 'draft_inventory_adjustment', 'update_invoice_status', 'update_order_status' => 'medium',
            'send_email' => 'low',
            default => 'low',
        };

        DB::table('ai_change_requests')->insert([
            'id'              => $actionId,
            'workspace_id'    => $workspaceId,
            'conversation_id' => $conversationId,
            'requested_by'    => $userId,
            'change_type'     => $changeType,
            'risk_level'      => $riskLevel,
            'status'          => 'proposed',
            'proposed_diff'   => json_encode([
                'tool'   => $name,
                'params' => $params,
            ]),
            'proposed_at'     => now(),
            'expires_at'      => now()->addHours(24),
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        return [
            'action'     => 'pending_confirmation',
            'action_id'  => $actionId,
            'tool'       => $name,
            'draft'      => $params,
            'message'    => 'Draft created. Please confirm or reject this action.',
            'expires_at' => now()->addHours(24)->toISOString(),
        ];
    }

    // ── Private ─────────────────────────────────────

    private function resolveContact(string $wsId, string $name): array
    {
        $contacts = DB::table('contacts')
            ->where('workspace_id', $wsId)
            ->where('name', 'ILIKE', "%{$name}%")
            ->select(['id', 'name', 'email', 'type'])
            ->limit(5)
            ->get();

        if ($contacts->isEmpty()) {
            return ['error' => 'no_match', 'message' => "No contact found matching '{$name}'."];
        }

        if ($contacts->count() === 1) {
            return ['contact' => $contacts->first()];
        }

        return ['ambiguous' => true, 'candidates' => $contacts->toArray()];
    }

    private function resolveProduct(string $wsId, string $name): array
    {
        $products = DB::table('products')
            ->where('workspace_id', $wsId)
            ->where(fn ($q) => $q->where('name', 'ILIKE', "%{$name}%")->orWhere('sku', 'ILIKE', "%{$name}%"))
            ->select(['id', 'name', 'sku', 'base_price'])
            ->limit(5)
            ->get();

        if ($products->count() === 1) {
            return ['match' => $products->first()];
        }

        if ($products->count() > 1) {
            return ['ambiguous' => true, 'candidates' => $products->toArray()];
        }

        return []; // No results = use raw name
    }
}
