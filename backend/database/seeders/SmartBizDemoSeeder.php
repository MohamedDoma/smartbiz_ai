<?php
namespace Database\Seeders;

use App\Models\BusinessTemplate;
use App\Models\Role;
use App\Models\User;
use App\Models\Workspace;
use App\Models\WorkspaceConfiguration;
use App\Services\BusinessTemplateApplicationService;
use App\Services\PermissionCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class SmartBizDemoSeeder
{
    const PW = 'SmartBiz@123456';
    const WS = 'dd000000-0000-0000-0000-000000000001';
    const CUR = 'SAR';

    /**
     * Canonical enabled-module keys for the demo workspace.
     *
     * Sourced from the automotive_dealer BusinessTemplate module list
     * (see BusinessTemplateSeeder). This is the single source of truth
     * for demo workspace module enablement.
     */
    const DEMO_ENABLED_MODULES = [
        'dashboard',
        'customers',
        'leads',
        'vehicle_sales',
        'spare_parts',
        'inventory',
        'invoices',
        'payments',
        'employees',
        'reports',
        'finance',
        'commissions',
        'ai',
    ];

    private string $pw;
    private array $userIds = [];
    private array $membershipIds = [];
    private array $roleIds = [];
    private array $deptIds = [];
    private array $teamIds = [];
    private array $catIds = [];
    private array $whIds = [];
    private array $prodIds = [];
    private array $contactIds = [];
    private string $pipelineId;
    private array $stageIds = [];

    public function run(): array
    {
        $this->pw = Hash::make(self::PW);
        $this->seedSuperAdmin();
        $this->seedWorkspace();
        $this->seedBusinessTemplates();
        $this->seedDepartments();
        $this->seedTeams();
        $this->seedRoles();
        $this->seedUsers();
        $this->seedMemberships();
        $this->seedMembershipRoles();
        $this->seedWarehouses();
        $this->seedCategories();
        $this->seedProducts();
        $this->seedInventory();
        $this->seedContacts();
        $this->seedPipeline();
        $this->seedPipelineRecords();
        $this->seedCommissionPlanAndRule();
        $this->seedInvoices();
        $this->seedPayments();
        $this->seedFinance();
        $this->seedActivationCampaign();
        $this->applyTemplateToWorkspace();
        $this->seedWorkspaceConfiguration();
        $this->enforceRolePermissions();
        return $this->summary();
    }

    private function ins(string $t, array $d): void
    {
        if (!Schema::hasTable($t)) return;
        DB::table($t)->insert($d);
    }

    private function now(): string { return now()->toDateTimeString(); }

    private function seedSuperAdmin(): void
{
    $id = '5a000000-0000-4000-8000-000000000001';

    $this->ins('users', [[
        'id' => $id,
        'full_name' => 'SmartBiz Super Admin',
        'phone_number' => '+218910000001',
        'email' => 'superadmin@smartbiz.test',
        'password_hash' => $this->pw,
        'is_super_admin' => true,
        'is_active' => true,
        'preferred_locale' => 'ar',
        'created_at' => $this->now(),
        'updated_at' => $this->now(),
    ]]);
}

    private function seedWorkspace(): void
    {
        $this->ins('workspaces', [[
            'id' => self::WS, 'name' => 'شركة سمارت بزنس التجريبية',
            'industry_type' => 'automotive', 'business_size' => 'medium',
            'default_locale' => 'ar', 'default_currency' => self::CUR, 'timezone' => 'Asia/Riyadh',
            'status' => 'active', 'is_active' => true, 'max_users' => 50,
            'created_at' => $this->now(), 'updated_at' => $this->now(),
        ]]);
    }

    private function seedDepartments(): void
    {
        $depts = ['الإدارة','المبيعات','المالية','المخزون','الموارد البشرية','خدمة العملاء'];
        foreach ($depts as $i => $n) {
            $id = Str::uuid()->toString();
            $this->deptIds[$i] = $id;
            $this->ins('departments', [[
                'id' => $id, 'workspace_id' => self::WS, 'name' => $n,
                'is_active' => true, 'sort_order' => $i, 'created_at' => $this->now(), 'updated_at' => $this->now(),
            ]]);
        }
    }

    private function seedTeams(): void
    {
        $teams = [
            ['فريق مبيعات السيارات', $this->deptIds[1] ?? null],
            ['فريق قطع الغيار', $this->deptIds[1] ?? null],
            ['فريق المستودع الرئيسي', $this->deptIds[3] ?? null],
        ];
        foreach ($teams as $i => [$n, $d]) {
            $id = Str::uuid()->toString();
            $this->teamIds[$i] = $id;
            $this->ins('teams', [[
                'id' => $id, 'workspace_id' => self::WS, 'department_id' => $d,
                'name' => $n, 'is_active' => true, 'sort_order' => $i,
                'created_at' => $this->now(), 'updated_at' => $this->now(),
            ]]);
        }
    }

    private function seedRoles(): void
    {
        // Derived from the canonical PermissionCatalog — prevents drift.
        $allPerms = PermissionCatalog::allKeys();
        $fin = ["accounting.view","invoices.list","invoices.show","invoices.create","invoices.update","payments.list","payments.show","payments.create","accounts.list","accounts.show","accounts.create","accounts.update","accounts.delete","journal_entries.list","journal_entries.show","journal_entries.create","journal_entries.update","recurring.list","recurring.show","recurring.create","recurring.update","recurring.delete","reports.view","notifications.list","notifications.update","commissions.list","commissions.view_all","commissions.calculate","commissions.approve","commissions.pay","commissions.cancel","commissions.settings.view","commissions.settings.manage"];
        $salesMgr = ["contacts.list","contacts.show","contacts.create","contacts.update","contacts.delete","contacts.own","contacts.manage_team","contacts.assign","products.list","products.show","invoices.list","invoices.show","invoices.create","invoices.update","orders.list","orders.show","orders.create","orders.update","notifications.list","notifications.update","pipelines.list","pipelines.manage","pipeline_records.create","pipeline_records.update","pipeline_records.delete","pipeline_records.own","pipeline_records.manage_team","pipeline_records.assign","commissions.list","commissions.view_team"];
        $salesAgent = ["contacts.list","contacts.show","contacts.create","contacts.update","contacts.delete","contacts.own","products.list","products.show","invoices.list","invoices.show","invoices.create","invoices.update","orders.list","orders.show","orders.create","orders.update","notifications.list","notifications.update","pipelines.list","pipeline_records.create","pipeline_records.update","pipeline_records.own","commissions.list","commissions.view_own","approvals.request","approvals.list","approvals.show"];
        $wh = ["warehouses.list","warehouses.show","warehouses.create","warehouses.update","warehouses.delete","inventory.list","inventory.show","inventory.create","reservations.list","reservations.show","reservations.create","reservations.update","products.list","products.show","notifications.list","notifications.update"];
        $cashierP = ["pos.view","invoices.list","invoices.show","invoices.create","orders.list","orders.show","contacts.list","contacts.show","products.list","products.show","notifications.list","notifications.update"];
        $hrP = ["employees.list","departments.list","teams.list","notifications.list","notifications.update","audit.list"];
        $empP = ["contacts.list","contacts.show","products.list","products.show","orders.list","orders.show","notifications.list","notifications.update"];
        $viewP = ["contacts.list","contacts.show","categories.list","categories.show","products.list","products.show","orders.list","orders.show","warehouses.list","warehouses.show","notifications.list"];

        $roles = [
            ['owner','Owner',$allPerms,1],['admin','Admin',$allPerms,2],
            ['general_manager','General Manager',$allPerms,3],
            ['sales_manager','Sales Manager',$salesMgr,4],
            ['sales_agent','Sales Agent',$salesAgent,5],
            ['accountant','Accountant',$fin,6],
            ['inventory_manager','Inventory Manager',array_merge($wh,["categories.list","categories.show"]),7],
            ['warehouse_staff','Warehouse Staff',$wh,8],
            ['cashier','Cashier',$cashierP,9],
            ['hr','HR',$hrP,10],
            ['department_head','Department Head',array_merge($empP,["audit.list"]),11],
            ['employee','Employee',$empP,12],
            ['viewer','Viewer',$viewP,13],
        ];
        foreach ($roles as [$key,$name,$perms,$sort]) {
            $id = Str::uuid()->toString();
            $this->roleIds[$key] = $id;
            $this->ins('roles', [[
                'id' => $id, 'workspace_id' => self::WS, 'name' => $name,
                'role_key' => $key, 'permissions' => json_encode(array_values(array_unique($perms))),
                'is_system' => true, 'is_default' => ($key === 'employee'),
                'is_deletable' => false, 'is_active' => true,
                'hierarchy_level' => $sort, 'sort_order' => $sort,
                'created_at' => $this->now(), 'updated_at' => $this->now(),
            ]]);
        }
    }

    private function seedUsers(): void
{
    $users = [
        ['owner', 'مالك الشركة', 'owner@demo.smartbiz.test', '+218910000002'],
        ['admin', 'مدير النظام', 'admin@demo.smartbiz.test', '+218910000003'],
        ['gm', 'المدير العام', 'general.manager@demo.smartbiz.test', '+218910000004'],
        ['sm', 'مدير المبيعات', 'sales.manager@demo.smartbiz.test', '+218910000005'],
        ['sa', 'وكيل المبيعات', 'sales.agent@demo.smartbiz.test', '+218910000006'],
        ['acc', 'المحاسب', 'accountant@demo.smartbiz.test', '+218910000007'],
        ['im', 'مدير المخزون', 'inventory.manager@demo.smartbiz.test', '+218910000008'],
        ['ws', 'موظف المستودع', 'warehouse.staff@demo.smartbiz.test', '+218910000009'],
        ['cash', 'الكاشير', 'cashier@demo.smartbiz.test', '+218910000010'],
        ['hr', 'الموارد البشرية', 'hr@demo.smartbiz.test', '+218910000011'],
        ['dh', 'رئيس القسم', 'department.head@demo.smartbiz.test', '+218910000012'],
        ['emp', 'موظف عادي', 'employee@demo.smartbiz.test', '+218910000013'],
        ['view', 'مستخدم للعرض فقط', 'viewer@demo.smartbiz.test', '+218910000014'],
    ];

    foreach ($users as [$k, $name, $email, $phoneNumber]) {
        $id = Str::uuid()->toString();

        $this->userIds[$k] = $id;

        $this->ins('users', [[
            'id' => $id,
            'full_name' => $name,
            'phone_number' => $phoneNumber,
            'email' => $email,
            'password_hash' => $this->pw,
            'is_super_admin' => false,
            'is_active' => true,
            'preferred_locale' => 'ar',
            'created_at' => $this->now(),
            'updated_at' => $this->now(),
        ]]);
    }
}

    private function seedMemberships(): void
    {
        $map = [
            'owner'=>[0,null],  'admin'=>[0,null],  'gm'=>[0,null],
            'sm'=>[1,0],        'sa'=>[1,0],        'acc'=>[2,null],
            'im'=>[3,null],     'ws'=>[3,2],        'cash'=>[5,null],
            'hr'=>[4,null],     'dh'=>[1,null],     'emp'=>[5,null],
            'view'=>[0,null],
        ];
        foreach ($map as $k => [$di,$ti]) {
            $id = Str::uuid()->toString();
            $this->membershipIds[$k] = $id;
            $this->ins('workspace_memberships', [[
                'id' => $id, 'workspace_id' => self::WS, 'user_id' => $this->userIds[$k],
                'department_id' => $this->deptIds[$di] ?? null,
                'team_id' => ($ti !== null ? ($this->teamIds[$ti] ?? null) : null),
                'status' => 'active', 'joined_at' => $this->now(),
                'created_at' => $this->now(), 'updated_at' => $this->now(),
            ]]);
        }
    }

    private function seedMembershipRoles(): void
    {
        $map = [
            'owner'=>'owner','admin'=>'admin','gm'=>'general_manager',
            'sm'=>'sales_manager','sa'=>'sales_agent','acc'=>'accountant',
            'im'=>'inventory_manager','ws'=>'warehouse_staff','cash'=>'cashier',
            'hr'=>'hr','dh'=>'department_head','emp'=>'employee','view'=>'viewer',
        ];
        foreach ($map as $uk => $rk) {
            $this->ins('membership_roles', [[
                'id' => Str::uuid()->toString(), 'workspace_id' => self::WS,
                'membership_id' => $this->membershipIds[$uk],
                'role_id' => $this->roleIds[$rk], 'is_primary' => true,
                'assigned_at' => $this->now(),
            ]]);
        }
    }

    private function seedWarehouses(): void
    {
        foreach ([['المستودع الرئيسي','الرياض - المنطقة الصناعية'],['معرض السيارات','الرياض - طريق الملك فهد']] as $i => [$n,$l]) {
            $id = Str::uuid()->toString();
            $this->whIds[$i] = $id;
            $this->ins('warehouses', [['id'=>$id,'workspace_id'=>self::WS,'name'=>$n,'location'=>$l]]);
        }
    }

    private function seedCategories(): void
    {
        foreach (['سيارات','قطع غيار'] as $i => $n) {
            $id = Str::uuid()->toString();
            $this->catIds[$i] = $id;
            $this->ins('product_categories', [['id'=>$id,'workspace_id'=>self::WS,'name'=>$n,'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    private function seedProducts(): void
    {
        $prods = [
    [$this->catIds[0], 'تويوتا كامري 2025', 'CAR-001', 'physical', 95000, 82000, 2],
    [$this->catIds[0], 'هيونداي توسان 2025', 'CAR-002', 'physical', 115000, 98000, 1],
    [$this->catIds[0], 'نيسان باترول 2024', 'CAR-003', 'physical', 220000, 195000, 1],
    [$this->catIds[1], 'فلتر زيت تويوتا', 'SP-001', 'physical', 45, 22, 120],
    [$this->catIds[1], 'بطارية فارتا 70 أمبير', 'SP-002', 'physical', 380, 280, 35],
    [$this->catIds[1], 'إطار ميشلان 205/55R16', 'SP-003', 'physical', 520, 390, 48],
    [$this->catIds[1], 'فرامل أمامية كامري', 'SP-004', 'physical', 350, 210, 25],
    [$this->catIds[1], 'فلتر هواء هيونداي', 'SP-005', 'physical', 65, 30, 80],
    [null, 'خدمة صيانة دورية', 'SVC-001', 'service', 250, 0, 0],
    [null, 'فحص كمبيوتر', 'SVC-002', 'service', 150, 0, 0],
];
        foreach ($prods as $i => [$cat,$name,$sku,$type,$price,$cost,$stock]) {
            $id = Str::uuid()->toString();
            $this->prodIds[$i] = ['id'=>$id,'stock'=>$stock,'price'=>$price,'name'=>$name,'sku'=>$sku];
            $row = ['id'=>$id,'workspace_id'=>self::WS,'category_id'=>$cat,'name'=>$name,'sku'=>$sku,
                'type'=>$type,'base_price'=>$price,'cost_price'=>$cost,'is_deleted'=>false,
                'min_stock_alert'=>($stock>0?max(1,(int)($stock*0.2)):null),
                'created_at'=>$this->now(),'updated_at'=>$this->now()];
            $this->ins('products', [$row]);
        }
    }

    private function seedInventory(): void
    {
        if (!Schema::hasTable('inventory_levels')) return;
        foreach ($this->prodIds as $p) {
            if ($p['stock'] <= 0) continue;
            $this->ins('inventory_levels', [[
                'id'=>Str::uuid()->toString(),'warehouse_id'=>$this->whIds[0],
                'product_id'=>$p['id'],'quantity'=>$p['stock'],
                'reserved'=>0,'available'=>$p['stock'],
                'workspace_id'=>self::WS,'updated_at'=>$this->now(),
            ]]);
        }
    }

    private function seedContacts(): void
    {
        $custs = [
            ['عبدالله المطيري','0551234567','abdullah@example.com','customer'],
            ['محمد الشهري','0559876543','mohammed@example.com','customer'],
            ['فهد العتيبي','0553456789','fahd@example.com','customer'],
            ['سارة الدوسري','0557654321','sara@example.com','customer'],
            ['خالد الغامدي','0552345678','khaled@example.com','customer'],
            ['نورة القحطاني','0558765432','noura@example.com','customer'],
            ['أحمد الزهراني','0554567890','ahmed@example.com','customer'],
            ['ريم الحربي','0556543210','reem@example.com','customer'],
            ['سلطان البلوي','0550123456','sultan@example.com','customer'],
            ['هند السبيعي','0559012345','hind@example.com','customer'],
            ['شركة تويوتا للقطع','0112345678','toyota@supplier.com','supplier'],
            ['مؤسسة الإطارات الحديثة','0119876543','tires@supplier.com','supplier'],
            ['شركة البطاريات المتحدة','0115432109','batteries@supplier.com','supplier'],
        ];
        // Customer contacts (indices 0-9) assigned alternately to SM/SA, matching pipeline records.
        // Supplier contacts (indices 10-12) remain unassigned (visible only via contacts.manage_all).
        $agents = ['sm','sa'];
        foreach ($custs as $i => [$n,$ph,$em,$tp]) {
            $id = Str::uuid()->toString();
            $this->contactIds[$i] = $id;
            $assignee = ($tp === 'customer') ? ($this->membershipIds[$agents[$i % 2]] ?? null) : null;
            $this->ins('contacts', [['id'=>$id,'workspace_id'=>self::WS,'type'=>$tp,'name'=>$n,'phone'=>$ph,'email'=>$em,'balance'=>0,'assigned_membership_id'=>$assignee,'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    private function seedPipeline(): void
    {
        $pid = Str::uuid()->toString();
        $this->pipelineId = $pid;
        $this->ins('pipelines', [['id'=>$pid,'workspace_id'=>self::WS,'pipeline_key'=>'car_sales','name'=>'مبيعات السيارات','entity_type'=>'deal','is_active'=>true,'sort_order'=>0,'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        $stages = ['عميل محتمل','تجربة السيارة','تفاوض','موافقة التمويل','دفع مقدم','تسليم','مكتمل','خاسر'];
        $types = ['open','open','open','open','open','open','won','lost'];
        foreach ($stages as $i => $s) {
            $sid = Str::uuid()->toString();
            $this->stageIds[$i] = $sid;
            $this->ins('pipeline_stages', [['id'=>$sid,'workspace_id'=>self::WS,'pipeline_id'=>$pid,'stage_key'=>'stage_'.$i,'name'=>$s,'status_type'=>$types[$i],'sort_order'=>$i,'is_active'=>true,'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    private function seedPipelineRecords(): void
    {
        $records = [
            ['صفقة كامري - عبدالله',0,0,95000,'open'],['صفقة توسان - محمد',1,1,115000,'open'],
            ['صفقة باترول - فهد',2,2,220000,'open'],['صفقة كامري - سارة',3,3,95000,'open'],
            ['صفقة توسان - خالد',4,4,115000,'open'],['صفقة كامري - نورة',6,5,95000,'won'],
            ['صفقة باترول - أحمد',6,6,220000,'won'],['صفقة توسان - ريم',6,7,115000,'won'],
            ['صفقة كامري - سلطان',7,8,95000,'lost'],['صفقة باترول - هند',7,9,220000,'lost'],
            ['قطع غيار - عبدالله',1,0,2500,'open'],['صيانة - محمد',5,1,850,'open'],
        ];
        $agents = ['sm','sa'];
        foreach ($records as $i => [$title,$si,$ci,$val,$status]) {
            $this->ins('pipeline_records', [['id'=>Str::uuid()->toString(),'workspace_id'=>self::WS,
                'pipeline_id'=>$this->pipelineId,'stage_id'=>$this->stageIds[$si],
                'title'=>$title,'contact_id'=>$this->contactIds[$ci] ?? null,
                'assigned_membership_id'=>$this->membershipIds[$agents[$i%2]] ?? null,
                'value_amount'=>$val,'currency'=>self::CUR,'status'=>$status,
                'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    /**
     * Create the demo commission plan and one percentage rule
     * for the automotive deal pipeline.
     *
     * Mirrors the identifiers used by:
     *   php artisan smartbiz:sync-demo-commission-rule
     */
    private function seedCommissionPlanAndRule(): void
    {
        if (!Schema::hasTable('commission_plans')) return;

        $planId = Str::uuid()->toString();
        $this->ins('commission_plans', [[
            'id'           => $planId,
            'workspace_id' => self::WS,
            'plan_key'     => 'demo_auto_sales_commission',
            'name'         => 'Demo Automotive Sales Commission',
            'description'  => 'Auto-generated demo commission plan for automotive sales.',
            'applies_to'   => 'pipeline_record',
            'is_active'    => true,
            'sort_order'   => 0,
            'created_at'   => $this->now(),
            'updated_at'   => $this->now(),
        ]]);

        $this->ins('commission_rules', [[
            'id'                 => Str::uuid()->toString(),
            'workspace_id'       => self::WS,
            'commission_plan_id' => $planId,
            'pipeline_id'        => $this->pipelineId,
            'stage_id'           => null,
            'role_id'            => null,
            'department_id'      => null,
            'team_id'            => null,
            'target_type'        => 'assigned_employee',
            'calculation_type'   => 'percentage',
            'percentage_rate'    => 2.0000,
            'fixed_amount'       => null,
            'currency'           => self::CUR,
            'min_record_value'   => null,
            'max_record_value'   => null,
            'trigger_status'     => 'won',
            'is_active'          => true,
            'sort_order'         => 0,
            'created_at'         => $this->now(),
            'updated_at'         => $this->now(),
        ]]);
    }

    private function seedInvoices(): void
    {
        $invs = [
            [5,95000,'paid'],[6,220000,'paid'],[7,115000,'paid'],
            [0,2500,'partial'],[1,850,'partial'],
            [2,520,'unpaid'],[3,380,'unpaid'],[4,45,'unpaid'],
        ];
        foreach ($invs as $i => [$ci,$amt,$ps]) {
            $iid = Str::uuid()->toString();
            $this->ins('invoices', [['id'=>$iid,'workspace_id'=>self::WS,
                'contact_id'=>$this->contactIds[$ci] ?? null,
                'created_by'=>$this->userIds['sa'] ?? null,
                'invoice_type'=>'sale','currency'=>self::CUR,'exchange_rate'=>1,
                'total_amount'=>$amt,'discount_amount'=>0,'net_amount'=>$amt,
                'tax_amount'=>$amt*0.15,'payment_status'=>$ps,
                'invoice_number'=>'INV-'.str_pad($i+1,4,'0',STR_PAD_LEFT),
                'due_date'=>now()->addDays(30)->toDateString(),
                'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
            // One invoice item per invoice (simplified)
            $pi = min($i, count($this->prodIds)-1);
            $this->ins('invoice_items', [['id'=>Str::uuid()->toString(),'invoice_id'=>$iid,
                'product_id'=>$this->prodIds[$pi]['id'],'quantity'=>1,
                'unit_price'=>$amt,'discount_amount'=>0,'tax_amount'=>$amt*0.15,
                'subtotal'=>$amt,'product_name_snapshot'=>$this->prodIds[$pi]['name'],
                'sku_snapshot'=>$this->prodIds[$pi]['sku']]]);
        }
    }

    private function seedPayments(): void
{
    $pays = [[5,95000],[6,220000],[7,115000],[0,1000],[1,400],[2,200]];

    foreach ($pays as $i => [$ci,$amt]) {
        $this->ins('payments', [[
            'id' => Str::uuid()->toString(),
            'workspace_id' => self::WS,
            'amount' => $amt,
            'payment_method' => ($i < 3 ? 'bank_transfer' : 'cash'),
            'status' => 'completed',
            'is_reversal' => false,
            'payment_number' => 'PAY-'.str_pad($i + 1, 4, '0', STR_PAD_LEFT),
            'payment_date' => now()->subDays(30 - $i)->toDateString(),
            'created_by' => $this->userIds['cash'] ?? null,
            'created_at' => $this->now(),
            'updated_at' => $this->now(),
        ]]);
    }
}

    private function seedFinance(): void
    {
        if (!Schema::hasTable('finance_accounts')) return;
        $accts = [
            ['cash','1001','الصندوق','asset','debit'],
            ['bank','1002','البنك الرئيسي','asset','debit'],
            ['ar','1100','ذمم مدينة','asset','debit'],
            ['revenue','4001','إيرادات المبيعات','revenue','credit'],
            ['cogs','5001','تكلفة البضاعة المباعة','expense','debit'],
            ['rent','6001','إيجار','expense','debit'],
            ['salaries','6002','رواتب','expense','debit'],
            ['marketing','6003','تسويق','expense','debit'],
            ['maintenance','6004','صيانة','expense','debit'],
            ['utilities','6005','مرافق','expense','debit'],
        ];
        foreach ($accts as [$key,$code,$name,$type,$nb]) {
            $this->ins('finance_accounts', [['id'=>Str::uuid()->toString(),'workspace_id'=>self::WS,
                'account_key'=>$key,'code'=>$code,'name'=>$name,'type'=>$type,
                'normal_balance'=>$nb,'is_system'=>true,'is_active'=>true,'sort_order'=>0,
                'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
        if (!Schema::hasTable('finance_expenses')) return;
        $exps = [['rent','إيجار المعرض',15000],['salaries','رواتب الموظفين',85000],
            ['marketing','حملة إعلانية',8000],['maintenance','صيانة المعرض',3500],
            ['utilities','كهرباء ومياه',4200]];
        foreach ($exps as [$cat,$desc,$amt]) {
            $this->ins('finance_expenses', [['id'=>Str::uuid()->toString(),'workspace_id'=>self::WS,
                'expense_date'=>now()->subDays(rand(1,30))->toDateString(),
                'category'=>$cat,'description'=>$desc,'amount'=>$amt,'currency'=>self::CUR,
                'payment_method'=>'bank_transfer','status'=>'approved',
                'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    private function seedActivationCampaign(): void
    {
        if (!Schema::hasTable('platform_activation_campaigns')) return;
        $cid = Str::uuid()->toString();
        $this->ins('platform_activation_campaigns', [['id'=>$cid,'campaign_key'=>'demo_2025',
            'name'=>'Demo Campaign','description'=>'حملة تجريبية','target_market'=>'saudi_arabia',
            'trial_days'=>14,'status'=>'active','created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        for ($i=1; $i<=5; $i++) {
            $this->ins('platform_activation_codes', [['id'=>Str::uuid()->toString(),'campaign_id'=>$cid,
                'code'=>'DEMO-'.str_pad($i,4,'0',STR_PAD_LEFT),'trial_days'=>14,
                'max_uses'=>1,'used_count'=>0,'status'=>'unused',
                'created_at'=>$this->now(),'updated_at'=>$this->now()]]);
        }
    }

    /**
     * Re-seed global business templates (truncated by demo-reset).
     */
    private function seedBusinessTemplates(): void
    {
        (new BusinessTemplateSeeder())->run();
    }

    /**
     * Apply the automotive_dealer template to the demo workspace.
     *
     * This creates: WorkspaceTemplateApplication (status=applied),
     * WorkspaceFeatureFlags, and sets onboarding_data.onboarding_completed=true.
     * The BusinessTemplateApplicationService also merges template role
     * permissions into existing workspace roles — we fix that in enforceRolePermissions().
     */
    private function applyTemplateToWorkspace(): void
    {
        $template = BusinessTemplate::where('template_key', 'automotive_dealer')->first();
        if (!$template) return;

        $workspace = Workspace::find(self::WS);
        if (!$workspace) return;

        // Use the owner user to apply the template
        $ownerUser = User::where('email', 'owner@demo.smartbiz.test')->first();
        if (!$ownerUser) return;

        $service = new BusinessTemplateApplicationService();
        $service->apply($template, $workspace, $ownerUser);
    }

    /**
     * Create or merge the WorkspaceConfiguration for the demo workspace.
     *
     * Idempotent behavior:
     *  - When no config exists: creates with canonical demo modules
     *    and valid empty defaults for other configuration fields.
     *  - When config already exists: merges missing canonical demo
     *    modules into enabled_modules without removing existing ones,
     *    and preserves all other configuration values untouched.
     */
    public function seedWorkspaceConfiguration(): void
    {
        $config = WorkspaceConfiguration::where('workspace_id', self::WS)->first();

        if (! $config) {
            WorkspaceConfiguration::create([
                'workspace_id'    => self::WS,
                'enabled_modules' => self::DEMO_ENABLED_MODULES,
                'role_configs'    => [],
                'pages'           => [],
                'workflows'       => [],
                'automations'     => [],
            ]);
            return;
        }

        // Merge: add missing canonical modules, preserve existing extras.
        $existing = $config->enabled_modules ?? [];
        $merged   = array_values(array_unique(array_merge($existing, self::DEMO_ENABLED_MODULES)));

        if ($merged !== $existing) {
            $config->update(['enabled_modules' => $merged]);
        }
    }

    /**
     * Re-enforce the exact demo role permission arrays.
     *
     * The template application service merges template-role permissions into
     * existing workspace roles (array_merge). This broadens restricted roles
     * like sales_manager and inventory_manager by adding reports.view, payments.list, etc.
     *
     * This method overwrites them back to the intended demo AI permission arrays.
     */
    private function enforceRolePermissions(): void
    {
        $salesMgr = ["contacts.list","contacts.show","contacts.create","contacts.update","contacts.delete","contacts.own","contacts.manage_team","contacts.assign","products.list","products.show","invoices.list","invoices.show","invoices.create","invoices.update","orders.list","orders.show","orders.create","orders.update","notifications.list","notifications.update","pipelines.list","pipelines.manage","pipeline_records.create","pipeline_records.update","pipeline_records.delete","pipeline_records.own","pipeline_records.manage_team","pipeline_records.assign","commissions.list","commissions.view_team"];
        $salesAgent = ["contacts.list","contacts.show","contacts.create","contacts.update","contacts.delete","contacts.own","products.list","products.show","invoices.list","invoices.show","invoices.create","invoices.update","orders.list","orders.show","orders.create","orders.update","notifications.list","notifications.update","pipelines.list","pipeline_records.create","pipeline_records.update","pipeline_records.own","commissions.list","commissions.view_own","approvals.request","approvals.list","approvals.show"];
        $wh = ["warehouses.list","warehouses.show","warehouses.create","warehouses.update","warehouses.delete","inventory.list","inventory.show","inventory.create","reservations.list","reservations.show","reservations.create","reservations.update","products.list","products.show","notifications.list","notifications.update"];
        $cashierP = ["pos.view","invoices.list","invoices.show","invoices.create","orders.list","orders.show","contacts.list","contacts.show","products.list","products.show","notifications.list","notifications.update"];
        $hrP = ["employees.list","departments.list","teams.list","notifications.list","notifications.update","audit.list"];
        $empP = ["contacts.list","contacts.show","products.list","products.show","orders.list","orders.show","notifications.list","notifications.update"];
        $viewP = ["contacts.list","contacts.show","categories.list","categories.show","products.list","products.show","orders.list","orders.show","warehouses.list","warehouses.show","notifications.list"];

        // Specialized sales agents (created by business template application):
        // Base = SALES_PERMS + pipeline perms + commissions.list
        $specializedSalesAgent = ["contacts.list","contacts.show","contacts.create","contacts.update","contacts.own","products.list","products.show","invoices.list","invoices.show","invoices.create","orders.list","orders.show","orders.create","payments.list","payments.show","inventory.list","inventory.show","notifications.list","notifications.update","pipelines.list","pipeline_records.create","pipeline_records.update","pipeline_records.own","commissions.list","commissions.view_own","approvals.request","approvals.list","approvals.show"];

        // Only override roles that must NOT have finance permissions
        $overrides = [
            'sales_manager'           => $salesMgr,
            'sales_agent'             => $salesAgent,
            'vehicle_sales_agent'     => $specializedSalesAgent,
            'spare_parts_sales_agent' => $specializedSalesAgent,
            'inventory_manager'=> array_values(array_unique(array_merge($wh, ["categories.list","categories.show"]))),
            'warehouse_staff'  => $wh,
            'cashier'          => $cashierP,
            'hr'               => $hrP,
            'department_head'  => array_values(array_unique(array_merge($empP, ["employees.list","audit.list"]))),
            'employee'         => $empP,
            'viewer'           => $viewP,
        ];

        foreach ($overrides as $roleKey => $perms) {
            Role::where('workspace_id', self::WS)
                ->where('role_key', $roleKey)
                ->update(['permissions' => json_encode(array_values(array_unique($perms)))]);
        }
    }


    private function summary(): array
    {
        return [
            'Workspace ID' => self::WS,
            'Workspace' => 'شركة سمارت بزنس التجريبية',
            'Users' => count($this->userIds) + 1,
            'Memberships' => count($this->membershipIds),
            'Roles' => count($this->roleIds),
            'Departments' => count($this->deptIds),
            'Teams' => count($this->teamIds),
            'Warehouses' => count($this->whIds),
            'Products' => count($this->prodIds),
            'Contacts' => count($this->contactIds),
            'Pipeline Records' => 12,
            'Invoices' => 8,
            'Payments' => 6,
        ];
    }
}
