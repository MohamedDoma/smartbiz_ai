<?php

namespace App\Services;

/**
 * Rule-based business classifier and ERP blueprint generator.
 *
 * Phase 1: Deterministic keyword/pattern matching.
 * Phase 2: Replace with LLM-powered classification.
 */
class BlueprintGeneratorService
{
    private const METHOD  = 'rule_based_v1';
    private const VERSION = '1.0.0';

    // ── Business type keyword maps ────────────────────────────────

    private const TYPE_KEYWORDS = [
        'retail' => [
            'shop', 'store', 'retail', 'pos', 'point of sale', 'cashier',
            'merchandise', 'boutique', 'mall', 'supermarket', 'grocery',
            'ecommerce', 'e-commerce', 'online store', 'selling products',
        ],
        'restaurant' => [
            'restaurant', 'cafe', 'food', 'kitchen', 'menu', 'dining',
            'catering', 'bar', 'hospitality', 'takeaway', 'delivery',
            'bakery', 'pizzeria', 'coffee', 'dine-in',
        ],
        'service' => [
            'service', 'consulting', 'agency', 'freelance', 'professional',
            'accounting firm', 'law firm', 'marketing', 'design', 'maintenance',
            'repair', 'cleaning', 'salon', 'spa', 'clinic', 'dental',
            'coaching', 'training', 'advisory',
        ],
        'manufacturing' => [
            'manufacturing', 'factory', 'production', 'assembly', 'fabrication',
            'plant', 'raw material', 'bom', 'bill of material', 'machinery',
            'processing', 'industrial', 'batch production',
        ],
        'distribution' => [
            'distribution', 'wholesale', 'distributor', 'logistics', 'supply chain',
            'warehousing', 'shipping', 'freight', 'import', 'export',
            'fleet', 'trucking', 'delivery service', 'fulfillment',
        ],
    ];

    // ── Discovery question categories ─────────────────────────────

    private const DISCOVERY_QUESTIONS = [
        'scale' => [
            'question' => 'How many employees does your business have?',
            'category' => 'scale',
        ],
        'locations' => [
            'question' => 'How many physical locations or branches do you operate?',
            'category' => 'locations',
        ],
        'products' => [
            'question' => 'Do you sell physical products, digital products, services, or a combination?',
            'category' => 'products',
        ],
        'inventory' => [
            'question' => 'Do you need to track inventory or stock levels?',
            'category' => 'inventory',
        ],
        'financial' => [
            'question' => 'Do you need to track invoices, payments, and accounting?',
            'category' => 'financial',
        ],
        'customers' => [
            'question' => 'Do you manage customer relationships or have a client database?',
            'category' => 'customers',
        ],
        'production' => [
            'question' => 'Do you manufacture or assemble products from raw materials?',
            'category' => 'production',
        ],
        'orders' => [
            'question' => 'Do you process sales orders, purchase orders, or both?',
            'category' => 'orders',
        ],
    ];

    // ═══════════════════════════════════════════════════════════════
    // Public API
    // ═══════════════════════════════════════════════════════════════

    /**
     * Generate follow-up questions based on what information is missing.
     */
    public function generateFollowUpQuestions(string $description, array $existingContext = []): array
    {
        $text = strtolower($description);
        foreach ($existingContext as $ctx) {
            $text .= ' ' . strtolower($ctx['content'] ?? '');
        }

        $asked = [];
        foreach ($existingContext as $ctx) {
            if (isset($ctx['meta']['questions'])) {
                foreach ($ctx['meta']['questions'] as $q) {
                    $asked[] = $q['category'] ?? '';
                }
            }
            if (isset($ctx['meta']['in_reply_to'])) {
                // Answers imply those categories are covered
            }
        }

        $questions = [];
        foreach (self::DISCOVERY_QUESTIONS as $key => $q) {
            // Skip if already asked
            if (in_array($q['category'], $asked)) continue;

            // Skip if description already hints at this
            if ($this->descriptionCoversCategory($text, $q['category'])) continue;

            $questions[] = $q;
            if (count($questions) >= 4) break; // Max 4 questions per round
        }

        return $questions;
    }

    /**
     * Classify the business type from description + context.
     */
    public function classifyBusiness(string $description, array $context = []): array
    {
        $fullText = strtolower($description);
        foreach ($context as $ctx) {
            $fullText .= ' ' . strtolower($ctx['content'] ?? '');
        }

        $scores = [];
        foreach (self::TYPE_KEYWORDS as $type => $keywords) {
            $score = 0;
            foreach ($keywords as $kw) {
                if (str_contains($fullText, $kw)) {
                    $score += 10;
                }
            }
            $scores[$type] = $score;
        }

        $maxScore = max($scores);
        $totalScore = array_sum($scores);

        if ($maxScore === 0) {
            return [
                'business_type' => 'service',  // safe default
                'confidence'    => 30.0,
                'scores'        => $scores,
                'method'        => self::METHOD,
                'version'       => self::VERSION,
            ];
        }

        // Check if hybrid (two types score within 30% of each other)
        $topTypes = array_filter($scores, fn($s) => $s >= $maxScore * 0.7 && $s > 0);
        if (count($topTypes) > 1) {
            $confidence = min(70.0, ($maxScore / max($totalScore, 1)) * 100);
            return [
                'business_type' => 'hybrid',
                'confidence'    => round($confidence, 2),
                'sub_types'     => array_keys($topTypes),
                'scores'        => $scores,
                'method'        => self::METHOD,
                'version'       => self::VERSION,
            ];
        }

        $bestType   = array_search($maxScore, $scores);
        $confidence = min(95.0, ($maxScore / max($totalScore, 1)) * 100);

        return [
            'business_type' => $bestType,
            'confidence'    => round(max($confidence, 50.0), 2),
            'scores'        => $scores,
            'method'        => self::METHOD,
            'version'       => self::VERSION,
        ];
    }

    /**
     * Generate a full ERP blueprint for the given business type.
     */
    public function generateBlueprint(string $businessType, string $description, array $context = []): array
    {
        $template = $this->getTemplate($businessType);

        // Enhance template with context-aware customizations
        $template = $this->enhanceWithContext($template, $description, $context);

        return $template;
    }

    // ═══════════════════════════════════════════════════════════════
    // Templates
    // ═══════════════════════════════════════════════════════════════

    private function getTemplate(string $type): array
    {
        return match ($type) {
            'retail'        => $this->retailTemplate(),
            'restaurant'    => $this->restaurantTemplate(),
            'service'       => $this->serviceTemplate(),
            'manufacturing' => $this->manufacturingTemplate(),
            'distribution'  => $this->distributionTemplate(),
            'hybrid'        => $this->hybridTemplate(),
            default         => $this->serviceTemplate(),
        };
    }

    private function retailTemplate(): array
    {
        return [
            'business_type' => 'retail',
            'enabled_modules' => [
                'contacts', 'product_categories', 'products', 'invoices', 'payments',
                'inventory', 'warehouses', 'orders', 'accounts', 'reports',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['recurring_expenses', 'journal_entries', 'bom'],
            'recommended_roles' => [
                ['name' => 'owner',             'description' => 'Full system access'],
                ['name' => 'admin',             'description' => 'Full system access, user management'],
                ['name' => 'store_manager',     'description' => 'Sales, inventory, limited reports'],
                ['name' => 'cashier',           'description' => 'POS, invoices, payments only'],
                ['name' => 'inventory_clerk',   'description' => 'Stock movements, warehouses only'],
                ['name' => 'accountant',        'description' => 'Financial reports, journals, accounts'],
            ],
            'role_homepages' => [
                'owner'           => '/dashboard',
                'admin'           => '/dashboard',
                'store_manager'   => '/sales',
                'cashier'         => '/pos',
                'inventory_clerk' => '/inventory',
                'accountant'      => '/finance',
            ],
            'role_navigation' => [
                'owner'           => ['dashboard', 'sales', 'inventory', 'finance', 'reports', 'settings'],
                'admin'           => ['dashboard', 'sales', 'inventory', 'finance', 'reports', 'settings'],
                'store_manager'   => ['sales', 'inventory', 'contacts', 'reports'],
                'cashier'         => ['pos', 'invoices', 'payments'],
                'inventory_clerk' => ['inventory', 'warehouses', 'products'],
                'accountant'      => ['finance', 'accounts', 'journals', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'           => ['create_invoice', 'view_reports', 'add_product', 'manage_users'],
                'store_manager'   => ['create_invoice', 'add_product', 'stock_check'],
                'cashier'         => ['new_sale', 'process_payment', 'refund'],
                'inventory_clerk' => ['receive_stock', 'stock_adjustment', 'transfer_stock'],
                'accountant'      => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'           => ['*'],
                'admin'           => ['*'],
                'store_manager'   => ['dashboard', 'contacts', 'products', 'invoices', 'orders', 'inventory', 'reports'],
                'cashier'         => ['pos', 'invoices', 'payments'],
                'inventory_clerk' => ['products', 'inventory', 'warehouses'],
                'accountant'      => ['accounts', 'journal_entries', 'payments', 'invoices', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'           => ['revenue_chart', 'top_products', 'stock_alerts', 'recent_invoices', 'daily_summary'],
                'store_manager'   => ['daily_sales', 'top_products', 'stock_alerts'],
                'cashier'         => ['todays_sales', 'recent_transactions'],
                'inventory_clerk' => ['stock_alerts', 'pending_receipts', 'low_stock'],
                'accountant'      => ['revenue_chart', 'receivables', 'payables', 'recent_journals'],
            ],
            'recommended_pages' => [
                'dashboard', 'pos', 'contacts', 'products', 'categories',
                'invoices', 'orders', 'payments', 'inventory', 'warehouses',
                'accounts', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'sale_to_payment',    'description' => 'Invoice → Payment → Receipt'],
                ['name' => 'purchase_to_stock',  'description' => 'Purchase Order → Receive → Stock In'],
                ['name' => 'return_refund',      'description' => 'Return → Credit Note → Refund'],
            ],
            'recommended_dashboards' => ['daily_sales', 'stock_alerts', 'top_products', 'revenue_trend'],
            'recommended_automations' => [
                ['name' => 'low_stock_alert',     'trigger' => 'Stock below threshold', 'action' => 'Send notification'],
                ['name' => 'daily_sales_report',  'trigger' => 'End of day',             'action' => 'Generate and email report'],
                ['name' => 'payment_reminder',    'trigger' => 'Invoice overdue',         'action' => 'Send reminder notification'],
            ],
            'assumptions' => [],
            'missing_info' => [],
        ];
    }

    private function restaurantTemplate(): array
    {
        return [
            'business_type' => 'restaurant',
            'enabled_modules' => [
                'contacts', 'product_categories', 'products', 'invoices', 'payments',
                'inventory', 'warehouses', 'orders', 'accounts', 'reports',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['recurring_expenses', 'journal_entries'],
            'recommended_roles' => [
                ['name' => 'owner',       'description' => 'Full system access'],
                ['name' => 'admin',       'description' => 'Full system access'],
                ['name' => 'manager',     'description' => 'Floor operations, reports, inventory'],
                ['name' => 'waiter',      'description' => 'Order taking, basic POS'],
                ['name' => 'kitchen',     'description' => 'Order queue, inventory usage'],
                ['name' => 'accountant',  'description' => 'Financial reports and journals'],
            ],
            'role_homepages' => [
                'owner'      => '/dashboard',
                'admin'      => '/dashboard',
                'manager'    => '/orders',
                'waiter'     => '/pos',
                'kitchen'    => '/kitchen-display',
                'accountant' => '/finance',
            ],
            'role_navigation' => [
                'owner'      => ['dashboard', 'orders', 'menu', 'inventory', 'finance', 'reports', 'settings'],
                'admin'      => ['dashboard', 'orders', 'menu', 'inventory', 'finance', 'reports', 'settings'],
                'manager'    => ['orders', 'menu', 'inventory', 'contacts', 'reports'],
                'waiter'     => ['pos', 'orders'],
                'kitchen'    => ['kitchen-display', 'inventory'],
                'accountant' => ['finance', 'accounts', 'journals', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'      => ['view_reports', 'manage_menu', 'manage_staff'],
                'manager'    => ['new_order', 'check_inventory', 'daily_report'],
                'waiter'     => ['new_order', 'process_payment'],
                'kitchen'    => ['mark_ready', 'request_stock'],
                'accountant' => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'      => ['*'],
                'admin'      => ['*'],
                'manager'    => ['dashboard', 'orders', 'products', 'inventory', 'contacts', 'reports'],
                'waiter'     => ['pos', 'orders'],
                'kitchen'    => ['kitchen-display', 'inventory'],
                'accountant' => ['accounts', 'journal_entries', 'payments', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'      => ['revenue_chart', 'daily_covers', 'top_dishes', 'stock_alerts', 'daily_summary'],
                'manager'    => ['active_orders', 'daily_sales', 'stock_alerts'],
                'waiter'     => ['active_orders', 'my_tables'],
                'kitchen'    => ['order_queue', 'stock_alerts'],
                'accountant' => ['revenue_chart', 'receivables', 'payables'],
            ],
            'recommended_pages' => [
                'dashboard', 'pos', 'orders', 'kitchen-display', 'menu',
                'inventory', 'contacts', 'payments', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'order_to_kitchen',   'description' => 'Order → Kitchen Queue → Serve → Pay'],
                ['name' => 'purchase_to_stock',  'description' => 'Supplier Order → Receive → Kitchen Stock'],
                ['name' => 'daily_close',        'description' => 'End of day → Cash count → Report → Close'],
            ],
            'recommended_dashboards' => ['daily_sales', 'order_queue', 'top_dishes', 'stock_alerts'],
            'recommended_automations' => [
                ['name' => 'low_ingredient_alert', 'trigger' => 'Ingredient below threshold', 'action' => 'Notify kitchen manager'],
                ['name' => 'daily_close_report',   'trigger' => 'End of business day',        'action' => 'Generate daily summary'],
            ],
            'assumptions' => [],
            'missing_info' => [],
        ];
    }

    private function serviceTemplate(): array
    {
        return [
            'business_type' => 'service',
            'enabled_modules' => [
                'contacts', 'invoices', 'payments', 'orders', 'accounts',
                'journal_entries', 'reports', 'recurring_expenses',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['products', 'product_categories', 'inventory', 'warehouses'],
            'recommended_roles' => [
                ['name' => 'owner',          'description' => 'Full system access'],
                ['name' => 'admin',          'description' => 'Full system access'],
                ['name' => 'project_manager','description' => 'Client management, orders, invoices'],
                ['name' => 'team_member',    'description' => 'View projects and tasks'],
                ['name' => 'accountant',     'description' => 'Financial reports, journals, payments'],
            ],
            'role_homepages' => [
                'owner'           => '/dashboard',
                'admin'           => '/dashboard',
                'project_manager' => '/clients',
                'team_member'     => '/tasks',
                'accountant'      => '/finance',
            ],
            'role_navigation' => [
                'owner'           => ['dashboard', 'clients', 'projects', 'invoices', 'finance', 'reports', 'settings'],
                'admin'           => ['dashboard', 'clients', 'projects', 'invoices', 'finance', 'reports', 'settings'],
                'project_manager' => ['clients', 'projects', 'invoices', 'reports'],
                'team_member'     => ['projects', 'tasks'],
                'accountant'      => ['finance', 'accounts', 'journals', 'invoices', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'           => ['create_invoice', 'add_client', 'view_reports'],
                'project_manager' => ['create_invoice', 'add_client', 'new_project'],
                'team_member'     => ['log_time', 'update_task'],
                'accountant'      => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'           => ['*'],
                'admin'           => ['*'],
                'project_manager' => ['dashboard', 'contacts', 'orders', 'invoices', 'payments', 'reports'],
                'team_member'     => ['orders'],
                'accountant'      => ['accounts', 'journal_entries', 'payments', 'invoices', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'           => ['revenue_chart', 'active_projects', 'receivables', 'recent_invoices'],
                'project_manager' => ['active_projects', 'pending_invoices', 'client_summary'],
                'team_member'     => ['my_tasks', 'upcoming_deadlines'],
                'accountant'      => ['revenue_chart', 'receivables', 'payables', 'cash_flow'],
            ],
            'recommended_pages' => [
                'dashboard', 'contacts', 'invoices', 'payments',
                'accounts', 'journals', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'client_to_invoice', 'description' => 'Client Onboard → Project → Invoice → Payment'],
                ['name' => 'expense_tracking',  'description' => 'Expense → Journal Entry → Report'],
            ],
            'recommended_dashboards' => ['revenue_trend', 'active_projects', 'receivables', 'cash_flow'],
            'recommended_automations' => [
                ['name' => 'invoice_reminder',   'trigger' => 'Invoice overdue 7 days',  'action' => 'Send reminder email'],
                ['name' => 'recurring_invoice',  'trigger' => 'Monthly cycle',           'action' => 'Generate recurring invoice'],
            ],
            'assumptions' => [],
            'missing_info' => [],
        ];
    }

    private function manufacturingTemplate(): array
    {
        return [
            'business_type' => 'manufacturing',
            'enabled_modules' => [
                'contacts', 'product_categories', 'products', 'invoices', 'payments',
                'inventory', 'warehouses', 'orders', 'bom', 'production_orders',
                'accounts', 'journal_entries', 'reports', 'stock_reservations',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['recurring_expenses'],
            'recommended_roles' => [
                ['name' => 'owner',              'description' => 'Full system access'],
                ['name' => 'admin',              'description' => 'Full system access'],
                ['name' => 'production_manager', 'description' => 'Production orders, BOM, inventory'],
                ['name' => 'warehouse_staff',    'description' => 'Stock movements, receiving, shipping'],
                ['name' => 'procurement',        'description' => 'Purchase orders, supplier contacts'],
                ['name' => 'accountant',         'description' => 'Financial reports, journals, accounts'],
            ],
            'role_homepages' => [
                'owner'              => '/dashboard',
                'admin'              => '/dashboard',
                'production_manager' => '/production',
                'warehouse_staff'    => '/inventory',
                'procurement'        => '/purchase-orders',
                'accountant'         => '/finance',
            ],
            'role_navigation' => [
                'owner'              => ['dashboard', 'production', 'inventory', 'sales', 'finance', 'reports', 'settings'],
                'admin'              => ['dashboard', 'production', 'inventory', 'sales', 'finance', 'reports', 'settings'],
                'production_manager' => ['production', 'bom', 'inventory', 'products', 'reports'],
                'warehouse_staff'    => ['inventory', 'warehouses', 'reservations'],
                'procurement'        => ['purchase-orders', 'contacts', 'products', 'inventory'],
                'accountant'         => ['finance', 'accounts', 'journals', 'invoices', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'              => ['create_production_order', 'view_reports', 'manage_bom'],
                'production_manager' => ['create_production_order', 'update_bom', 'stock_check'],
                'warehouse_staff'    => ['receive_stock', 'ship_order', 'stock_adjustment'],
                'procurement'        => ['create_purchase_order', 'add_supplier'],
                'accountant'         => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'              => ['*'],
                'admin'              => ['*'],
                'production_manager' => ['dashboard', 'production_orders', 'bom', 'products', 'inventory', 'reports'],
                'warehouse_staff'    => ['inventory', 'warehouses', 'stock_reservations', 'products'],
                'procurement'        => ['orders', 'contacts', 'products', 'inventory'],
                'accountant'         => ['accounts', 'journal_entries', 'payments', 'invoices', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'              => ['production_status', 'revenue_chart', 'stock_alerts', 'order_pipeline'],
                'production_manager' => ['active_production', 'material_availability', 'stock_alerts'],
                'warehouse_staff'    => ['pending_receipts', 'low_stock', 'pending_shipments'],
                'procurement'        => ['pending_orders', 'supplier_lead_times'],
                'accountant'         => ['revenue_chart', 'receivables', 'payables', 'cost_analysis'],
            ],
            'recommended_pages' => [
                'dashboard', 'contacts', 'products', 'categories', 'bom',
                'production-orders', 'inventory', 'warehouses', 'orders',
                'invoices', 'payments', 'accounts', 'journals', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'production_cycle', 'description' => 'BOM → Production Order → Material Reservation → Produce → Stock In'],
                ['name' => 'purchase_cycle',   'description' => 'Purchase Order → Receive → Quality Check → Stock In'],
                ['name' => 'sales_cycle',      'description' => 'Sales Order → Reserve → Ship → Invoice → Payment'],
            ],
            'recommended_dashboards' => ['production_status', 'stock_alerts', 'material_availability', 'order_pipeline'],
            'recommended_automations' => [
                ['name' => 'low_material_alert',     'trigger' => 'Raw material below threshold', 'action' => 'Notify procurement'],
                ['name' => 'production_completion',  'trigger' => 'Production order completed',   'action' => 'Update inventory, notify warehouse'],
            ],
            'assumptions' => [],
            'missing_info' => [],
        ];
    }

    private function distributionTemplate(): array
    {
        return [
            'business_type' => 'distribution',
            'enabled_modules' => [
                'contacts', 'product_categories', 'products', 'invoices', 'payments',
                'inventory', 'warehouses', 'orders', 'stock_reservations',
                'accounts', 'journal_entries', 'reports',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['bom', 'production_orders', 'recurring_expenses'],
            'recommended_roles' => [
                ['name' => 'owner',            'description' => 'Full system access'],
                ['name' => 'admin',            'description' => 'Full system access'],
                ['name' => 'sales_rep',        'description' => 'Customer orders, invoices'],
                ['name' => 'warehouse_manager','description' => 'Inventory, shipping, receiving'],
                ['name' => 'logistics',        'description' => 'Shipment tracking, delivery'],
                ['name' => 'accountant',       'description' => 'Financial reports and accounting'],
            ],
            'role_homepages' => [
                'owner'             => '/dashboard',
                'admin'             => '/dashboard',
                'sales_rep'         => '/orders',
                'warehouse_manager' => '/inventory',
                'logistics'         => '/shipments',
                'accountant'        => '/finance',
            ],
            'role_navigation' => [
                'owner'             => ['dashboard', 'orders', 'inventory', 'finance', 'reports', 'settings'],
                'admin'             => ['dashboard', 'orders', 'inventory', 'finance', 'reports', 'settings'],
                'sales_rep'         => ['orders', 'contacts', 'invoices', 'products'],
                'warehouse_manager' => ['inventory', 'warehouses', 'reservations', 'products'],
                'logistics'         => ['shipments', 'orders', 'warehouses'],
                'accountant'        => ['finance', 'accounts', 'journals', 'invoices', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'             => ['view_reports', 'create_order', 'manage_warehouses'],
                'sales_rep'         => ['create_order', 'create_invoice', 'add_customer'],
                'warehouse_manager' => ['receive_stock', 'ship_order', 'stock_transfer'],
                'logistics'         => ['update_shipment', 'track_delivery'],
                'accountant'        => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'             => ['*'],
                'admin'             => ['*'],
                'sales_rep'         => ['orders', 'contacts', 'invoices', 'payments', 'products'],
                'warehouse_manager' => ['inventory', 'warehouses', 'stock_reservations', 'products', 'orders'],
                'logistics'         => ['orders', 'warehouses', 'inventory'],
                'accountant'        => ['accounts', 'journal_entries', 'payments', 'invoices', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'             => ['revenue_chart', 'order_pipeline', 'stock_alerts', 'shipment_status'],
                'sales_rep'         => ['my_orders', 'pending_invoices', 'top_customers'],
                'warehouse_manager' => ['pending_shipments', 'low_stock', 'incoming_stock'],
                'logistics'         => ['active_shipments', 'delivery_schedule'],
                'accountant'        => ['revenue_chart', 'receivables', 'payables', 'cash_flow'],
            ],
            'recommended_pages' => [
                'dashboard', 'contacts', 'products', 'categories', 'orders',
                'invoices', 'payments', 'inventory', 'warehouses',
                'accounts', 'journals', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'order_to_delivery',  'description' => 'Order → Reserve → Pick → Ship → Invoice → Payment'],
                ['name' => 'purchase_to_stock',  'description' => 'Purchase → Receive → QC → Stock In'],
                ['name' => 'return_process',     'description' => 'Return → Inspect → Restock or Write-off → Credit'],
            ],
            'recommended_dashboards' => ['order_pipeline', 'stock_alerts', 'shipment_tracking', 'revenue_trend'],
            'recommended_automations' => [
                ['name' => 'reorder_alert',     'trigger' => 'Stock below reorder point', 'action' => 'Notify procurement'],
                ['name' => 'shipment_tracking', 'trigger' => 'Order shipped',             'action' => 'Notify customer'],
            ],
            'assumptions' => [],
            'missing_info' => [],
        ];
    }

    private function hybridTemplate(): array
    {
        // Combine the most comprehensive modules from all types
        return [
            'business_type' => 'hybrid',
            'enabled_modules' => [
                'contacts', 'product_categories', 'products', 'invoices', 'payments',
                'inventory', 'warehouses', 'orders', 'accounts', 'journal_entries',
                'reports', 'recurring_expenses', 'stock_reservations',
                'notifications', 'audit_logs',
            ],
            'optional_modules' => ['bom', 'production_orders'],
            'recommended_roles' => [
                ['name' => 'owner',      'description' => 'Full system access'],
                ['name' => 'admin',      'description' => 'Full system access'],
                ['name' => 'manager',    'description' => 'Operations management'],
                ['name' => 'sales',      'description' => 'Sales and invoicing'],
                ['name' => 'warehouse',  'description' => 'Inventory management'],
                ['name' => 'accountant', 'description' => 'Financial management'],
            ],
            'role_homepages' => [
                'owner'      => '/dashboard',
                'admin'      => '/dashboard',
                'manager'    => '/dashboard',
                'sales'      => '/orders',
                'warehouse'  => '/inventory',
                'accountant' => '/finance',
            ],
            'role_navigation' => [
                'owner'      => ['dashboard', 'sales', 'inventory', 'finance', 'reports', 'settings'],
                'admin'      => ['dashboard', 'sales', 'inventory', 'finance', 'reports', 'settings'],
                'manager'    => ['dashboard', 'sales', 'inventory', 'contacts', 'reports'],
                'sales'      => ['orders', 'invoices', 'contacts', 'products'],
                'warehouse'  => ['inventory', 'warehouses', 'products'],
                'accountant' => ['finance', 'accounts', 'journals', 'reports'],
            ],
            'role_quick_actions' => [
                'owner'      => ['create_invoice', 'view_reports', 'add_product'],
                'manager'    => ['create_invoice', 'stock_check', 'daily_report'],
                'sales'      => ['create_order', 'create_invoice', 'add_customer'],
                'warehouse'  => ['receive_stock', 'ship_order', 'stock_adjustment'],
                'accountant' => ['record_payment', 'create_journal', 'view_reports'],
            ],
            'role_allowed_screens' => [
                'owner'      => ['*'],
                'admin'      => ['*'],
                'manager'    => ['dashboard', 'contacts', 'products', 'orders', 'invoices', 'inventory', 'reports'],
                'sales'      => ['orders', 'invoices', 'contacts', 'products', 'payments'],
                'warehouse'  => ['inventory', 'warehouses', 'products', 'stock_reservations'],
                'accountant' => ['accounts', 'journal_entries', 'payments', 'invoices', 'reports'],
            ],
            'role_dashboard_widgets' => [
                'owner'      => ['revenue_chart', 'top_products', 'stock_alerts', 'order_pipeline', 'daily_summary'],
                'manager'    => ['daily_sales', 'stock_alerts', 'pending_orders'],
                'sales'      => ['my_orders', 'pending_invoices', 'top_customers'],
                'warehouse'  => ['stock_alerts', 'pending_shipments', 'low_stock'],
                'accountant' => ['revenue_chart', 'receivables', 'payables', 'cash_flow'],
            ],
            'recommended_pages' => [
                'dashboard', 'contacts', 'products', 'categories', 'orders',
                'invoices', 'payments', 'inventory', 'warehouses',
                'accounts', 'journals', 'reports', 'settings',
            ],
            'recommended_workflows' => [
                ['name' => 'sale_to_payment',   'description' => 'Order → Invoice → Payment → Receipt'],
                ['name' => 'purchase_to_stock', 'description' => 'Purchase → Receive → Stock In'],
            ],
            'recommended_dashboards' => ['revenue_trend', 'stock_alerts', 'order_pipeline', 'daily_summary'],
            'recommended_automations' => [
                ['name' => 'low_stock_alert',   'trigger' => 'Stock below threshold', 'action' => 'Send notification'],
                ['name' => 'invoice_reminder',  'trigger' => 'Invoice overdue',       'action' => 'Send reminder'],
            ],
            'assumptions' => ['Business operates across multiple verticals'],
            'missing_info' => [],
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    // Context Enhancement
    // ═══════════════════════════════════════════════════════════════

    private function enhanceWithContext(array $template, string $description, array $context): array
    {
        $fullText = strtolower($description);
        foreach ($context as $ctx) {
            $fullText .= ' ' . strtolower($ctx['content'] ?? '');
        }

        // Add assumptions based on context clues
        if (str_contains($fullText, 'single location') || str_contains($fullText, 'one location') || str_contains($fullText, 'one branch')) {
            $template['assumptions'][] = 'Single location operation';
        }
        if (str_contains($fullText, 'multiple') && (str_contains($fullText, 'location') || str_contains($fullText, 'branch'))) {
            $template['assumptions'][] = 'Multi-location operation';
            if (! in_array('warehouses', $template['enabled_modules'])) {
                $template['enabled_modules'][] = 'warehouses';
            }
        }
        if (str_contains($fullText, 'online') || str_contains($fullText, 'ecommerce') || str_contains($fullText, 'e-commerce')) {
            $template['assumptions'][] = 'Online sales channel active';
        }

        // Detect missing info
        if (! str_contains($fullText, 'employee') && ! str_contains($fullText, 'staff') && ! str_contains($fullText, 'team')) {
            $template['missing_info'][] = 'Number of employees/team members';
        }
        if (! str_contains($fullText, 'location') && ! str_contains($fullText, 'branch') && ! str_contains($fullText, 'office')) {
            $template['missing_info'][] = 'Number of physical locations';
        }

        return $template;
    }

    // ═══════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════

    private function descriptionCoversCategory(string $text, string $category): bool
    {
        return match ($category) {
            'scale'      => str_contains($text, 'employee') || str_contains($text, 'staff') || str_contains($text, 'team'),
            'locations'  => str_contains($text, 'location') || str_contains($text, 'branch') || str_contains($text, 'office'),
            'products'   => str_contains($text, 'product') || str_contains($text, 'service') || str_contains($text, 'item'),
            'inventory'  => str_contains($text, 'inventory') || str_contains($text, 'stock') || str_contains($text, 'warehouse'),
            'financial'  => str_contains($text, 'invoice') || str_contains($text, 'payment') || str_contains($text, 'account'),
            'customers'  => str_contains($text, 'customer') || str_contains($text, 'client') || str_contains($text, 'buyer'),
            'production' => str_contains($text, 'manufact') || str_contains($text, 'assembly') || str_contains($text, 'production'),
            'orders'     => str_contains($text, 'order') || str_contains($text, 'purchase order') || str_contains($text, 'sales order'),
            default      => false,
        };
    }
}
