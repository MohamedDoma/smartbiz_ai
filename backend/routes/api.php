<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AiChatController;
use App\Http\Controllers\Api\AiFoundationController;
use App\Http\Controllers\Api\PlatformAiUsageController;
use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BomController;
use App\Http\Controllers\Api\BusinessTemplateController;
use App\Http\Controllers\Api\ContactController;
use App\Http\Controllers\Api\DiscoveryController;
use App\Http\Controllers\Api\ProvisioningController;
use App\Http\Controllers\Api\SuperAdminController;
use App\Http\Controllers\Api\WebhookController;
use App\Http\Middleware\CheckAiCredits;
use App\Http\Middleware\SuperAdminMiddleware;
use App\Http\Controllers\Api\InventoryMovementController;
use App\Http\Controllers\Api\InvoiceController;
use App\Http\Controllers\Api\JournalEntryController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\OrderController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\ProductCategoryController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\ProductionOrderController;
use App\Http\Controllers\Api\RecurringExpenseController;
use App\Http\Controllers\Api\ReportingController;
use App\Http\Controllers\Api\StockReservationController;
use App\Http\Controllers\Api\WarehouseController;
use App\Http\Controllers\Api\WorkspaceInvitationController;
use App\Http\Controllers\Api\RoleManagementController;
use App\Http\Controllers\Api\WorkspaceEmployeeRoleController;
use App\Http\Controllers\Api\DepartmentController;
use App\Http\Controllers\Api\TeamController;
use App\Http\Controllers\Api\PipelineController;
use App\Http\Controllers\Api\PipelineStageController;
use App\Http\Controllers\Api\PipelineRecordController;
use App\Http\Controllers\Api\CustomFieldController;
use App\Http\Controllers\Api\DocumentChecklistController;
use App\Http\Controllers\Api\DocumentChecklistItemController;
use App\Http\Controllers\Api\RecordDocumentController;
use App\Http\Controllers\Api\CommissionPlanController;
use App\Http\Controllers\Api\CommissionRuleController;
use App\Http\Controllers\Api\CommissionEntryController;
use App\Http\Controllers\Api\CommissionSettingsController;
use App\Http\Controllers\Api\OwnershipController;
use App\Http\Controllers\Api\DuplicateRuleController;
use App\Http\Controllers\Api\DuplicateMatchController;
use App\Http\Controllers\Api\ReportCatalogController;
use App\Http\Controllers\Api\ReportTemplateController;
use App\Http\Controllers\Api\ReportRunController;
use App\Http\Controllers\Api\FinanceAccountController;
use App\Http\Controllers\Api\FinanceTransactionController;
use App\Http\Controllers\Api\FinanceExpenseController;
use App\Http\Controllers\Api\FinanceSummaryController;
use App\Http\Controllers\Api\PlatformDashboardController;
use App\Http\Controllers\Api\PlatformWorkspaceController;
use App\Http\Controllers\Api\PlatformUserController;
use App\Http\Controllers\Api\PlatformActivationCampaignController;
use App\Http\Controllers\Api\PlatformActivationCodeController;
use App\Http\Controllers\Api\PlatformSystemHealthController;
use App\Http\Controllers\Api\ApprovalController;
use App\Http\Controllers\Api\ApprovalEntityFieldCatalogController;
use App\Http\Controllers\Api\ApprovalWorkflowController;
use App\Http\Middleware\CheckPermission;
use App\Http\Middleware\SetWorkspaceContext;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| SmartBiz AI — API Routes
|--------------------------------------------------------------------------
|
| Public routes: auth/login
| Authenticated routes: auth/logout, auth/me
| Workspace-scoped routes: require X-Workspace-Id header
|
*/

// ── Public ──────────────────────────────────────────────────────

// Health check (unauthenticated — for load balancers & monitoring)
Route::get('/health', \App\Http\Controllers\Api\HealthController::class)
    ->name('health');

Route::post('/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:auth')
    ->name('auth.login');

Route::post('/auth/register', [AuthController::class, 'register'])
    ->middleware('throttle:auth')
    ->name('auth.register');

// ── Public Invite Endpoints ────────────────────────────────────
Route::get('/invites/{token}', [WorkspaceInvitationController::class, 'preview'])
    ->name('invites.preview');
Route::post('/invites/{token}/accept', [WorkspaceInvitationController::class, 'accept'])
    ->middleware('throttle:auth')
    ->name('invites.accept');

// ── Public Activation Code Validation ──────────────────────────
Route::get('/activation-codes/{code}', [PlatformActivationCodeController::class, 'publicShow'])
    ->name('activation-codes.public-show');
Route::post('/activation-codes/{code}/validate', [PlatformActivationCodeController::class, 'publicValidate'])
    ->name('activation-codes.public-validate');

// ── Authenticated (no workspace required) ───────────────────────

Route::middleware('auth:sanctum')->group(function () {

    Route::post('/auth/logout', [AuthController::class, 'logout'])
        ->name('auth.logout');

    Route::get('/auth/me', [AuthController::class, 'me'])
        ->name('auth.me');

    // ── Business Templates (read-only, no workspace required) ───

    Route::get('/business-templates', [BusinessTemplateController::class, 'index'])
        ->name('templates.index');

    Route::get('/business-templates/{template_key}', [BusinessTemplateController::class, 'show'])
        ->name('templates.show');

    Route::post('/business-templates/{template_key}/apply', [BusinessTemplateController::class, 'apply'])
        ->name('templates.apply');

    // ── Workspace-Scoped (requires X-Workspace-Id header) ───────

    Route::middleware(SetWorkspaceContext::class)->group(function () {

        // Ping
        Route::get('/ping', function (Request $request) {
            $ctx = app(WorkspaceContextManager::class);
            return response()->json([
                'status'        => 'ok',
                'workspace_id'  => $ctx->workspaceId(),
                'membership_id' => $ctx->membershipId(),
                'user_id'       => $request->user()->id,
            ]);
        })->name('workspace.ping');

        // ── Contacts ────────────────────────────────────────────
        Route::prefix('contacts')->group(function () {
            Route::get('/assignable-members', [ContactController::class, 'assignableMembers'])->middleware(CheckPermission::class . ':contacts.assign')->name('contacts.assignable-members');
            Route::get('/',     [ContactController::class, 'index'])->middleware(CheckPermission::class . ':contacts.list')->name('contacts.index');
            Route::get('/{id}', [ContactController::class, 'show'])->middleware(CheckPermission::class . ':contacts.show')->name('contacts.show');
            Route::post('/',    [ContactController::class, 'store'])->middleware(CheckPermission::class . ':contacts.create')->name('contacts.store');
            Route::put('/{id}', [ContactController::class, 'update'])->middleware(CheckPermission::class . ':contacts.update')->name('contacts.update');
            Route::delete('/{id}', [ContactController::class, 'destroy'])->middleware(CheckPermission::class . ':contacts.delete')->name('contacts.destroy');
        });

        // ── Product Categories ──────────────────────────────────
        Route::prefix('product-categories')->group(function () {
            Route::get('/',     [ProductCategoryController::class, 'index'])->middleware(CheckPermission::class . ':categories.list')->name('categories.index');
            Route::get('/{id}', [ProductCategoryController::class, 'show'])->middleware(CheckPermission::class . ':categories.show')->name('categories.show');
            Route::post('/',    [ProductCategoryController::class, 'store'])->middleware(CheckPermission::class . ':categories.create')->name('categories.store');
            Route::put('/{id}', [ProductCategoryController::class, 'update'])->middleware(CheckPermission::class . ':categories.update')->name('categories.update');
            Route::delete('/{id}', [ProductCategoryController::class, 'destroy'])->middleware(CheckPermission::class . ':categories.delete')->name('categories.destroy');
        });

        // ── Products ────────────────────────────────────────────
        Route::prefix('products')->group(function () {
            Route::get('/',     [ProductController::class, 'index'])->middleware(CheckPermission::class . ':products.list')->name('products.index');
            Route::get('/{id}', [ProductController::class, 'show'])->middleware(CheckPermission::class . ':products.show')->name('products.show');
            Route::post('/',    [ProductController::class, 'store'])->middleware(CheckPermission::class . ':products.create')->name('products.store');
            Route::put('/{id}', [ProductController::class, 'update'])->middleware(CheckPermission::class . ':products.update')->name('products.update');
            Route::delete('/{id}', [ProductController::class, 'destroy'])->middleware(CheckPermission::class . ':products.delete')->name('products.destroy');
        });

        // ── Invoices (no delete — financial records are immutable) ─
        Route::prefix('invoices')->group(function () {
            Route::get('/',     [InvoiceController::class, 'index'])->middleware(CheckPermission::class . ':invoices.list')->name('invoices.index');
            Route::get('/{id}', [InvoiceController::class, 'show'])->middleware(CheckPermission::class . ':invoices.show')->name('invoices.show');
            Route::post('/',    [InvoiceController::class, 'store'])->middleware(CheckPermission::class . ':invoices.create')->name('invoices.store');
            Route::put('/{id}', [InvoiceController::class, 'update'])->middleware(CheckPermission::class . ':invoices.update')->name('invoices.update');
        });

        // ── Accounts (Chart of Accounts) ────────────────────────
        Route::prefix('accounts')->group(function () {
            Route::get('/',     [AccountController::class, 'index'])->middleware(CheckPermission::class . ':accounts.list')->name('accounts.index');
            Route::get('/{id}', [AccountController::class, 'show'])->middleware(CheckPermission::class . ':accounts.show')->name('accounts.show');
            Route::post('/',    [AccountController::class, 'store'])->middleware(CheckPermission::class . ':accounts.create')->name('accounts.store');
            Route::put('/{id}', [AccountController::class, 'update'])->middleware(CheckPermission::class . ':accounts.update')->name('accounts.update');
            Route::delete('/{id}', [AccountController::class, 'destroy'])->middleware(CheckPermission::class . ':accounts.delete')->name('accounts.destroy');
        });

        // ── Orders (no delete — business records) ───────────────
        Route::prefix('orders')->group(function () {
            Route::get('/',     [OrderController::class, 'index'])->middleware(CheckPermission::class . ':orders.list')->name('orders.index');
            Route::get('/{id}', [OrderController::class, 'show'])->middleware(CheckPermission::class . ':orders.show')->name('orders.show');
            Route::post('/',    [OrderController::class, 'store'])->middleware(CheckPermission::class . ':orders.create')->name('orders.store');
            Route::put('/{id}', [OrderController::class, 'update'])->middleware(CheckPermission::class . ':orders.update')->name('orders.update');
        });

        // ── Journal Entries (no delete — financial immutable) ───
        Route::prefix('journal-entries')->group(function () {
            Route::get('/',     [JournalEntryController::class, 'index'])->middleware(CheckPermission::class . ':journal_entries.list')->name('journal_entries.index');
            Route::get('/{id}', [JournalEntryController::class, 'show'])->middleware(CheckPermission::class . ':journal_entries.show')->name('journal_entries.show');
            Route::post('/',    [JournalEntryController::class, 'store'])->middleware(CheckPermission::class . ':journal_entries.create')->name('journal_entries.store');
            Route::put('/{id}', [JournalEntryController::class, 'update'])->middleware(CheckPermission::class . ':journal_entries.update')->name('journal_entries.update');
        });

        // ── Warehouses ──────────────────────────────────────────
        Route::prefix('warehouses')->group(function () {
            Route::get('/',     [WarehouseController::class, 'index'])->middleware(CheckPermission::class . ':warehouses.list')->name('warehouses.index');
            Route::get('/{id}', [WarehouseController::class, 'show'])->middleware(CheckPermission::class . ':warehouses.show')->name('warehouses.show');
            Route::post('/',    [WarehouseController::class, 'store'])->middleware(CheckPermission::class . ':warehouses.create')->name('warehouses.store');
            Route::put('/{id}', [WarehouseController::class, 'update'])->middleware(CheckPermission::class . ':warehouses.update')->name('warehouses.update');
            Route::delete('/{id}', [WarehouseController::class, 'destroy'])->middleware(CheckPermission::class . ':warehouses.delete')->name('warehouses.destroy');
        });

        // ── Payments (no delete — financial records) ────────────
        Route::prefix('payments')->group(function () {
            Route::get('/',     [PaymentController::class, 'index'])->middleware(CheckPermission::class . ':payments.list')->name('payments.index');
            Route::get('/{id}', [PaymentController::class, 'show'])->middleware(CheckPermission::class . ':payments.show')->name('payments.show');
            Route::post('/',    [PaymentController::class, 'store'])->middleware(CheckPermission::class . ':payments.create')->name('payments.store');
            Route::post('/{id}/reverse', [PaymentController::class, 'reverse'])->middleware(CheckPermission::class . ':payments.create')->name('payments.reverse');
        });

        // ── Inventory Movements (immutable — no update/delete) ──
        Route::prefix('inventory-movements')->group(function () {
            Route::get('/',       [InventoryMovementController::class, 'index'])->middleware(CheckPermission::class . ':inventory.list')->name('inventory_movements.index');
            Route::get('/levels', [InventoryMovementController::class, 'levels'])->middleware(CheckPermission::class . ':inventory.list')->name('inventory.levels');
            Route::get('/{id}',   [InventoryMovementController::class, 'show'])->middleware(CheckPermission::class . ':inventory.show')->name('inventory_movements.show');
            Route::post('/',      [InventoryMovementController::class, 'store'])->middleware(CheckPermission::class . ':inventory.create')->name('inventory_movements.store');
        });

        // ── Stock Reservations ──────────────────────────────────
        Route::prefix('stock-reservations')->group(function () {
            Route::get('/',     [StockReservationController::class, 'index'])->middleware(CheckPermission::class . ':reservations.list')->name('reservations.index');
            Route::get('/{id}', [StockReservationController::class, 'show'])->middleware(CheckPermission::class . ':reservations.show')->name('reservations.show');
            Route::post('/',    [StockReservationController::class, 'store'])->middleware(CheckPermission::class . ':reservations.create')->name('reservations.store');
            Route::post('/{id}/release', [StockReservationController::class, 'release'])->middleware(CheckPermission::class . ':reservations.update')->name('reservations.release');
            Route::post('/{id}/fulfill', [StockReservationController::class, 'fulfill'])->middleware(CheckPermission::class . ':reservations.update')->name('reservations.fulfill');
        });

        // ── Bill of Materials (BOM) ────────────────────────────
        Route::prefix('bom')->group(function () {
            Route::get('/',     [BomController::class, 'index'])->middleware(CheckPermission::class . ':bom.list')->name('bom.index');
            Route::get('/{id}', [BomController::class, 'show'])->middleware(CheckPermission::class . ':bom.show')->name('bom.show');
            Route::post('/',    [BomController::class, 'store'])->middleware(CheckPermission::class . ':bom.create')->name('bom.store');
            Route::put('/{id}', [BomController::class, 'update'])->middleware(CheckPermission::class . ':bom.update')->name('bom.update');
            Route::delete('/{id}', [BomController::class, 'destroy'])->middleware(CheckPermission::class . ':bom.delete')->name('bom.destroy');
        });

        // ── Production Orders (no delete — business records) ───
        Route::prefix('production-orders')->group(function () {
            Route::get('/',     [ProductionOrderController::class, 'index'])->middleware(CheckPermission::class . ':production.list')->name('production.index');
            Route::get('/{id}', [ProductionOrderController::class, 'show'])->middleware(CheckPermission::class . ':production.show')->name('production.show');
            Route::post('/',    [ProductionOrderController::class, 'store'])->middleware(CheckPermission::class . ':production.create')->name('production.store');
            Route::put('/{id}', [ProductionOrderController::class, 'update'])->middleware(CheckPermission::class . ':production.update')->name('production.update');
        });

        // ── Recurring Expenses ─────────────────────────────────
        Route::prefix('recurring-expenses')->group(function () {
            Route::get('/',     [RecurringExpenseController::class, 'index'])->middleware(CheckPermission::class . ':recurring.list')->name('recurring.index');
            Route::get('/{id}', [RecurringExpenseController::class, 'show'])->middleware(CheckPermission::class . ':recurring.show')->name('recurring.show');
            Route::post('/',    [RecurringExpenseController::class, 'store'])->middleware(CheckPermission::class . ':recurring.create')->name('recurring.store');
            Route::put('/{id}', [RecurringExpenseController::class, 'update'])->middleware(CheckPermission::class . ':recurring.update')->name('recurring.update');
            Route::delete('/{id}', [RecurringExpenseController::class, 'destroy'])->middleware(CheckPermission::class . ':recurring.delete')->name('recurring.destroy');
        });

        // ── Notifications ──────────────────────────────────────
        Route::prefix('notifications')->group(function () {
            Route::get('/',          [NotificationController::class, 'index'])->middleware(CheckPermission::class . ':notifications.list')->name('notifications.index');
            Route::post('/{id}/read', [NotificationController::class, 'markRead'])->middleware(CheckPermission::class . ':notifications.update')->name('notifications.read');
            Route::post('/read-all', [NotificationController::class, 'markAllRead'])->middleware(CheckPermission::class . ':notifications.update')->name('notifications.readAll');
        });

        // ── Audit Logs (read-only) ─────────────────────────────
        Route::prefix('audit-logs')->group(function () {
            Route::get('/',     [AuditLogController::class, 'index'])->middleware(CheckPermission::class . ':audit.list')->name('audit.index');
            Route::get('/{id}', [AuditLogController::class, 'show'])->middleware(CheckPermission::class . ':audit.show')->name('audit.show');
        });

        // ── Reporting / Analytics ──────────────────────────────
        Route::prefix('reports')->group(function () {
            Route::get('/sales',             [ReportingController::class, 'salesSummary'])->middleware(CheckPermission::class . ':reports.view')->name('reports.sales');
            Route::get('/invoices-payments', [ReportingController::class, 'invoicePaymentSummary'])->middleware(CheckPermission::class . ':reports.view')->name('reports.invoices');
            Route::get('/inventory',         [ReportingController::class, 'inventorySummary'])->middleware(CheckPermission::class . ':reports.view')->name('reports.inventory');
            Route::get('/account-balances',  [ReportingController::class, 'accountBalances'])->middleware(CheckPermission::class . ':reports.view')->name('reports.accounts');
            Route::get('/receivable-payable',[ReportingController::class, 'receivablePayable'])->middleware(CheckPermission::class . ':reports.view')->name('reports.receivable');
        });

        // ── AI Discovery Sessions ──────────────────────────────────
        Route::prefix('discovery/sessions')->middleware(CheckPermission::class . ':discovery.manage')->group(function () {
            Route::get('/',                          [DiscoveryController::class, 'index'])->name('discovery.index');
            Route::get('/{id}',                      [DiscoveryController::class, 'show'])->name('discovery.show');
            Route::post('/',                         [DiscoveryController::class, 'start'])->name('discovery.start');
            Route::post('/{id}/answer',              [DiscoveryController::class, 'answer'])->name('discovery.answer');
            Route::post('/{id}/classify',            [DiscoveryController::class, 'classify'])->name('discovery.classify');
            Route::post('/{id}/generate-blueprint',  [DiscoveryController::class, 'generateBlueprint'])->name('discovery.generate');
            Route::get('/{id}/blueprint',            [DiscoveryController::class, 'showBlueprint'])->name('discovery.blueprint');
        });

        // ── ERP Provisioning ───────────────────────────────────────
        Route::prefix('provisioning')->middleware(CheckPermission::class . ':discovery.manage')->group(function () {
            Route::post('/preview',       [ProvisioningController::class, 'preview'])->name('provisioning.preview');
            Route::post('/apply',         [ProvisioningController::class, 'apply'])->name('provisioning.apply');
            Route::post('/rollback',      [ProvisioningController::class, 'rollback'])->name('provisioning.rollback');
            Route::get('/config',         [ProvisioningController::class, 'config'])->name('provisioning.config');
            Route::put('/modules',        [ProvisioningController::class, 'updateModules'])->name('provisioning.modules');
            Route::put('/roles/{role}',   [ProvisioningController::class, 'updateRole'])->name('provisioning.roles');
        });

        // ── Manual Payment Submission ──────────────────────────────
        Route::post('/billing/manual-payment', [SuperAdminController::class, 'submitManualPayment'])
            ->name('billing.manual-payment');

        // ── AI Chat ──────────────────────────────────────────────────
        Route::prefix('ai')->middleware('throttle:ai')->group(function () {
            Route::post('/chat',           [AiChatController::class, 'chat'])->middleware(CheckAiCredits::class . ':ai_chat')->name('ai.chat');
            Route::get('/history',         [AiChatController::class, 'history'])->name('ai.history');
            Route::post('/confirm-action', [AiChatController::class, 'confirmAction'])->name('ai.confirm');
            Route::post('/reject-action',  [AiChatController::class, 'rejectAction'])->name('ai.reject');
            Route::get('/insights',                [AiChatController::class, 'insights'])->name('ai.insights');
            Route::post('/insights/generate',      [AiChatController::class, 'generateInsights'])->name('ai.insights.generate');
            Route::post('/insights/{id}/dismiss',  [AiChatController::class, 'dismissInsight'])->name('ai.insights.dismiss');

            // AI Advisor
            Route::get('/advisor/recommendations',   [\App\Http\Controllers\Api\AiAdvisorController::class, 'index'])->name('ai.advisor.recommendations');
            Route::post('/advisor/run-analysis',     [\App\Http\Controllers\Api\AiAdvisorController::class, 'runAnalysis'])->name('ai.advisor.run');
            Route::post('/advisor/{id}/accept',      [\App\Http\Controllers\Api\AiAdvisorController::class, 'accept'])->name('ai.advisor.accept');
            Route::post('/advisor/{id}/reject',      [\App\Http\Controllers\Api\AiAdvisorController::class, 'reject'])->name('ai.advisor.reject');
            Route::post('/advisor/{id}/apply',       [\App\Http\Controllers\Api\AiAdvisorController::class, 'apply'])->name('ai.advisor.apply');
        });

        // ── AI Foundation (Step 59.1) — non-conflicting utilities ────
        Route::prefix('ai')->group(function () {
            Route::post('/test',              [AiFoundationController::class, 'test'])->name('ai.foundation.test');
            // /chat is handled by AiChatController above (the canonical route)
            Route::get('/conversations',      [AiFoundationController::class, 'conversations'])->name('ai.foundation.conversations');
            Route::get('/conversations/{id}', [AiFoundationController::class, 'showConversation'])->name('ai.foundation.conversation');
        });

        // ── Workspace Invitations ──────────────────────────────────
        Route::prefix('workspace-invitations')->group(function () {
            Route::get('/',             [WorkspaceInvitationController::class, 'index'])->name('workspace-invitations.index');
            Route::post('/',            [WorkspaceInvitationController::class, 'store'])->name('workspace-invitations.store');
            Route::post('/{id}/revoke', [WorkspaceInvitationController::class, 'revoke'])->name('workspace-invitations.revoke');
        });

        // ── Workspace Roles (CRUD + permission catalog) ──────────
        Route::get('/permission-catalog', [RoleManagementController::class, 'permissionCatalog'])
            ->name('permission-catalog.index');
        Route::prefix('workspace-roles')->group(function () {
            Route::get('/',               [RoleManagementController::class, 'index'])->name('workspace-roles.index');
            Route::post('/',              [RoleManagementController::class, 'store'])->name('workspace-roles.store');
            Route::put('/{id}',           [RoleManagementController::class, 'update'])->name('workspace-roles.update');
            Route::post('/{id}/deactivate', [RoleManagementController::class, 'deactivate'])->name('workspace-roles.deactivate');
        });

        // ── Workspace Employees (role assignment + org assignment) ─
        Route::prefix('workspace-employees')->group(function () {
            Route::get('/',                    [WorkspaceEmployeeRoleController::class, 'index'])->name('workspace-employees.index');
            Route::put('/{id}/roles',          [WorkspaceEmployeeRoleController::class, 'updateRoles'])->name('workspace-employees.updateRoles');
            Route::put('/{id}/assignment',     [WorkspaceEmployeeRoleController::class, 'updateAssignment'])->name('workspace-employees.updateAssignment');
        });

        // ── Departments ───────────────────────────────────────────
        Route::prefix('departments')->group(function () {
            Route::get('/',     [DepartmentController::class, 'index'])->name('departments.index');
            Route::post('/',    [DepartmentController::class, 'store'])->name('departments.store');
            Route::get('/{id}', [DepartmentController::class, 'show'])->name('departments.show');
            Route::put('/{id}', [DepartmentController::class, 'update'])->name('departments.update');
            Route::delete('/{id}', [DepartmentController::class, 'destroy'])->name('departments.destroy');
        });

        // ── Teams ──────────────────────────────────────────────────
        Route::prefix('teams')->group(function () {
            Route::get('/',     [TeamController::class, 'index'])->name('teams.index');
            Route::post('/',    [TeamController::class, 'store'])->name('teams.store');
            Route::get('/{id}', [TeamController::class, 'show'])->name('teams.show');
            Route::put('/{id}', [TeamController::class, 'update'])->name('teams.update');
            Route::delete('/{id}', [TeamController::class, 'destroy'])->name('teams.destroy');
        });

        // ── Pipelines ─────────────────────────────────────────────
        Route::prefix('pipelines')->group(function () {
            Route::get('/',     [PipelineController::class, 'index'])->middleware(CheckPermission::class . ':pipelines.list')->name('pipelines.index');
            Route::post('/',    [PipelineController::class, 'store'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipelines.store');
            Route::get('/{id}', [PipelineController::class, 'show'])->middleware(CheckPermission::class . ':pipelines.list')->name('pipelines.show');
            Route::put('/{id}', [PipelineController::class, 'update'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipelines.update');
            Route::delete('/{id}', [PipelineController::class, 'destroy'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipelines.destroy');

            // Nested stages
            Route::get('/{pipelineId}/stages',  [PipelineStageController::class, 'index'])->middleware(CheckPermission::class . ':pipelines.list')->name('pipeline-stages.index');
            Route::post('/{pipelineId}/stages', [PipelineStageController::class, 'store'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipeline-stages.store');
        });

        // ── Pipeline Stages (standalone) ───────────────────────────
        Route::put('/pipeline-stages/{id}',    [PipelineStageController::class, 'update'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipeline-stages.update');
        Route::delete('/pipeline-stages/{id}', [PipelineStageController::class, 'destroy'])->middleware(CheckPermission::class . ':pipelines.manage')->name('pipeline-stages.destroy');

        // ── Pipeline Records ──────────────────────────────────────
        Route::prefix('pipeline-records')->group(function () {
            Route::get('/assignable-members', [PipelineRecordController::class, 'assignableMembers'])->middleware(CheckPermission::class . ':pipeline_records.assign')->name('pipeline-records.assignable-members');
            Route::get('/',        [PipelineRecordController::class, 'index'])->middleware(CheckPermission::class . ':pipelines.list')->name('pipeline-records.index');
            Route::post('/',       [PipelineRecordController::class, 'store'])->middleware(CheckPermission::class . ':pipeline_records.create')->name('pipeline-records.store');
            Route::get('/{id}',    [PipelineRecordController::class, 'show'])->middleware(CheckPermission::class . ':pipelines.list')->name('pipeline-records.show');
            Route::put('/{id}',    [PipelineRecordController::class, 'update'])->middleware(CheckPermission::class . ':pipeline_records.update')->name('pipeline-records.update');
            Route::post('/{id}/move', [PipelineRecordController::class, 'move'])->middleware(CheckPermission::class . ':pipeline_records.update')->name('pipeline-records.move');
            Route::delete('/{id}', [PipelineRecordController::class, 'destroy'])->middleware(CheckPermission::class . ':pipeline_records.delete')->name('pipeline-records.destroy');

            // Nested record documents
            Route::get('/{recordId}/documents',       [RecordDocumentController::class, 'index'])->middleware(CheckPermission::class . ':pipelines.list')->name('record-documents.index');
            Route::post('/{recordId}/documents',      [RecordDocumentController::class, 'store'])->middleware(CheckPermission::class . ':pipeline_records.update')->name('record-documents.store');
            Route::get('/{recordId}/document-status',  [RecordDocumentController::class, 'documentStatus'])->middleware(CheckPermission::class . ':pipelines.list')->name('record-documents.status');
            Route::post('/{recordId}/calculate-commissions', [CommissionEntryController::class, 'calculateForRecord'])->name('commission-entries.calculate');
        });

        // ── Custom Fields ─────────────────────────────────────────
        Route::prefix('custom-fields')->group(function () {
            Route::get('/',     [CustomFieldController::class, 'index'])->middleware(CheckPermission::class . ':pipelines.list')->name('custom-fields.index');
            Route::post('/',    [CustomFieldController::class, 'store'])->middleware(CheckPermission::class . ':pipelines.manage')->name('custom-fields.store');
            Route::get('/{id}', [CustomFieldController::class, 'show'])->middleware(CheckPermission::class . ':pipelines.list')->name('custom-fields.show');
            Route::put('/{id}', [CustomFieldController::class, 'update'])->middleware(CheckPermission::class . ':pipelines.manage')->name('custom-fields.update');
            Route::delete('/{id}', [CustomFieldController::class, 'destroy'])->middleware(CheckPermission::class . ':pipelines.manage')->name('custom-fields.destroy');
        });

        // ── Document Checklists ───────────────────────────────
        Route::prefix('document-checklists')->group(function () {
            Route::get('/',     [DocumentChecklistController::class, 'index'])->name('document-checklists.index');
            Route::post('/',    [DocumentChecklistController::class, 'store'])->name('document-checklists.store');
            Route::get('/{id}', [DocumentChecklistController::class, 'show'])->name('document-checklists.show');
            Route::put('/{id}', [DocumentChecklistController::class, 'update'])->name('document-checklists.update');
            Route::delete('/{id}', [DocumentChecklistController::class, 'destroy'])->name('document-checklists.destroy');

            // Nested items
            Route::get('/{checklistId}/items',  [DocumentChecklistItemController::class, 'index'])->name('document-checklist-items.index');
            Route::post('/{checklistId}/items', [DocumentChecklistItemController::class, 'store'])->name('document-checklist-items.store');
        });

        // ── Document Checklist Items (standalone) ─────────────────
        Route::put('/document-checklist-items/{id}',    [DocumentChecklistItemController::class, 'update'])->name('document-checklist-items.update');
        Route::delete('/document-checklist-items/{id}', [DocumentChecklistItemController::class, 'destroy'])->name('document-checklist-items.destroy');

        // ── Record Documents (standalone) ───────────────────────
        Route::delete('/record-documents/{id}', [RecordDocumentController::class, 'destroy'])->middleware(CheckPermission::class . ':pipeline_records.delete')->name('record-documents.destroy');

        // ── Commission Settings Options ───────────────────
        Route::get("commission-settings/options", [CommissionSettingsController::class, "options"])->name("commission-settings.options");

        // ── Commission Plans ───────────────────────────────
        Route::prefix('commission-plans')->group(function () {
            Route::get('/',     [CommissionPlanController::class, 'index'])->name('commission-plans.index');
            Route::post('/',    [CommissionPlanController::class, 'store'])->name('commission-plans.store');
            Route::get('/{id}', [CommissionPlanController::class, 'show'])->name('commission-plans.show');
            Route::put('/{id}', [CommissionPlanController::class, 'update'])->name('commission-plans.update');
            Route::delete('/{id}', [CommissionPlanController::class, 'destroy'])->name('commission-plans.destroy');
        });

        // ── Commission Rules ───────────────────────────────
        Route::prefix('commission-rules')->group(function () {
            Route::get('/',     [CommissionRuleController::class, 'index'])->name('commission-rules.index');
            Route::post('/',    [CommissionRuleController::class, 'store'])->name('commission-rules.store');
            Route::get('/{id}', [CommissionRuleController::class, 'show'])->name('commission-rules.show');
            Route::put('/{id}', [CommissionRuleController::class, 'update'])->name('commission-rules.update');
            Route::delete('/{id}', [CommissionRuleController::class, 'destroy'])->name('commission-rules.destroy');
        });

        // ── Commission Entries ─────────────────────────────
        Route::prefix('commission-entries')->group(function () {
            Route::get('/',     [CommissionEntryController::class, 'index'])->name('commission-entries.index');
            Route::get('/{id}', [CommissionEntryController::class, 'show'])->name('commission-entries.show');
            Route::post('/{id}/mark-approved', [CommissionEntryController::class, 'markApproved'])->name('commission-entries.approve');
            Route::post('/{id}/mark-paid',     [CommissionEntryController::class, 'markPaid'])->name('commission-entries.pay');
            Route::post('/{id}/cancel',        [CommissionEntryController::class, 'cancel'])->name('commission-entries.cancel');
        });

        // ── Ownership Assignments ───────────────────────
        Route::prefix('ownership-assignments')->group(function () {
            Route::get('/',     [OwnershipController::class, 'index'])->name('ownership.index');
            Route::post('/',    [OwnershipController::class, 'store'])->name('ownership.store');
            Route::get('/{id}', [OwnershipController::class, 'show'])->name('ownership.show');
            Route::put('/{id}/transfer', [OwnershipController::class, 'transfer'])->name('ownership.transfer');
        });
        Route::get('/ownership/resolve', [OwnershipController::class, 'resolve'])->name('ownership.resolve');

        // ── Duplicate Rules ────────────────────────────
        Route::prefix('duplicate-rules')->group(function () {
            Route::get('/',     [DuplicateRuleController::class, 'index'])->name('duplicate-rules.index');
            Route::post('/',    [DuplicateRuleController::class, 'store'])->name('duplicate-rules.store');
            Route::get('/{id}', [DuplicateRuleController::class, 'show'])->name('duplicate-rules.show');
            Route::put('/{id}', [DuplicateRuleController::class, 'update'])->name('duplicate-rules.update');
            Route::delete('/{id}', [DuplicateRuleController::class, 'destroy'])->name('duplicate-rules.destroy');
        });

        // ── Duplicate Checks & Matches ─────────────────
        Route::post('/duplicates/check', [DuplicateMatchController::class, 'check'])->name('duplicates.check');
        Route::get('/duplicate-matches', [DuplicateMatchController::class, 'index'])->name('duplicate-matches.index');
        Route::post('/duplicate-matches/{id}/resolve', [DuplicateMatchController::class, 'resolve'])->name('duplicate-matches.resolve');

        // ── Report Catalog ────────────────────────────
        Route::get('/report-catalog',               [ReportCatalogController::class, 'index'])->name('report-catalog.index');
        Route::get('/report-catalog/{data_source}', [ReportCatalogController::class, 'show'])->name('report-catalog.show');

        // ── Report Templates ──────────────────────────
        Route::prefix('report-templates')->group(function () {
            Route::get('/',         [ReportTemplateController::class, 'index'])->name('report-templates.index');
            Route::post('/',        [ReportTemplateController::class, 'store'])->name('report-templates.store');
            Route::get('/{id}',     [ReportTemplateController::class, 'show'])->name('report-templates.show');
            Route::put('/{id}',     [ReportTemplateController::class, 'update'])->name('report-templates.update');
            Route::delete('/{id}',  [ReportTemplateController::class, 'destroy'])->name('report-templates.destroy');
            Route::post('/{id}/run', [ReportTemplateController::class, 'run'])->name('report-templates.run');
        });

        // ── Report Runs ───────────────────────────────
        Route::get('/report-runs',      [ReportRunController::class, 'index'])->name('report-runs.index');
        Route::get('/report-runs/{id}', [ReportRunController::class, 'show'])->name('report-runs.show');
        Route::post('/reports/run',     [ReportRunController::class, 'runAdHoc'])->name('reports.run-adhoc');

        // ── Finance ──────────────────────────────────────
        Route::prefix('finance')->group(function () {
            Route::get('/accounts',              [FinanceAccountController::class, 'index'])->name('finance.accounts.index');
            Route::post('/accounts',             [FinanceAccountController::class, 'store'])->name('finance.accounts.store');
            Route::put('/accounts/{id}',         [FinanceAccountController::class, 'update'])->name('finance.accounts.update');
            Route::post('/bootstrap',            [FinanceAccountController::class, 'bootstrap'])->name('finance.bootstrap');

            Route::get('/transactions',          [FinanceTransactionController::class, 'index'])->name('finance.transactions.index');
            Route::get('/transactions/{id}',     [FinanceTransactionController::class, 'show'])->name('finance.transactions.show');
            Route::post('/transactions',         [FinanceTransactionController::class, 'store'])->name('finance.transactions.store');
            Route::post('/transactions/{id}/void', [FinanceTransactionController::class, 'void'])->name('finance.transactions.void');

            Route::get('/expenses',              [FinanceExpenseController::class, 'index'])->name('finance.expenses.index');
            Route::post('/expenses',             [FinanceExpenseController::class, 'store'])->name('finance.expenses.store');
            Route::get('/expenses/{id}',         [FinanceExpenseController::class, 'show'])->name('finance.expenses.show');
            Route::post('/expenses/{id}/void',   [FinanceExpenseController::class, 'void'])->name('finance.expenses.void');

            Route::get('/summary',               [FinanceSummaryController::class, 'summary'])->name('finance.summary');
            Route::get('/profit-loss',           [FinanceSummaryController::class, 'profitLoss'])->name('finance.profit-loss');
            Route::get('/account-balances',      [FinanceSummaryController::class, 'accountBalances'])->name('finance.account-balances');
        });

        // ── Finance Posting Integrations ──────────────────
        Route::post('/commission-entries/{id}/post-to-finance', [FinanceTransactionController::class, 'postCommissionEntry'])->name('finance.post-commission');
        Route::post('/invoices/{id}/post-to-finance',           [FinanceTransactionController::class, 'postInvoice'])->name('finance.post-invoice');
        Route::post('/payments/{id}/post-to-finance',           [FinanceTransactionController::class, 'postPayment'])->name('finance.post-payment');

        // ── Approval Workflows (admin CRUD) ──────────────────
        Route::prefix('approval-workflows')->middleware(CheckPermission::class . ':approvals.manage')->group(function () {
            Route::get('/',     [ApprovalWorkflowController::class, 'index'])->name('approval-workflows.index');
            Route::post('/',    [ApprovalWorkflowController::class, 'store'])->name('approval-workflows.store');
            Route::get('/{id}', [ApprovalWorkflowController::class, 'show'])->name('approval-workflows.show');
            Route::put('/{id}', [ApprovalWorkflowController::class, 'update'])->name('approval-workflows.update');
            Route::delete('/{id}', [ApprovalWorkflowController::class, 'destroy'])->name('approval-workflows.destroy');

            // Nested steps
            Route::post('/{workflowId}/steps', [ApprovalWorkflowController::class, 'addStep'])->name('approval-workflow-steps.store');
        });

        // ── Approval Workflow Steps (standalone update/delete) ─
        Route::put('/approval-workflow-steps/{id}',    [ApprovalWorkflowController::class, 'updateStep'])->middleware(CheckPermission::class . ':approvals.manage')->name('approval-workflow-steps.update');
        Route::delete('/approval-workflow-steps/{id}', [ApprovalWorkflowController::class, 'deleteStep'])->middleware(CheckPermission::class . ':approvals.manage')->name('approval-workflow-steps.destroy');

        // ── Approval Entity Field Catalog (condition builder schema) ─
        Route::get('/approval-entity-field-catalog', [ApprovalEntityFieldCatalogController::class, 'index'])->middleware(CheckPermission::class . ':approvals.manage')->name('approval-entity-field-catalog.index');

        // ── Approval Entity Types (discovery endpoint for condition builder) ─
        Route::get('/approval-entity-types', [ApprovalEntityFieldCatalogController::class, 'entityTypes'])->middleware(CheckPermission::class . ':approvals.manage')->name('approval-entity-types.index');

        // ── Approval Requests (lifecycle) ────────────────────
        Route::prefix('approvals')->group(function () {
            Route::get('/inbox', [ApprovalController::class, 'inbox'])->middleware(CheckPermission::class . ':approvals.list')->name('approvals.inbox');
            Route::get('/',      [ApprovalController::class, 'index'])->middleware(CheckPermission::class . ':approvals.list')->name('approvals.index');
            Route::get('/{id}',  [ApprovalController::class, 'show'])->middleware(CheckPermission::class . ':approvals.show')->name('approvals.show');
            Route::post('/',     [ApprovalController::class, 'store'])->middleware(CheckPermission::class . ':approvals.request')->name('approvals.store');
            Route::post('/{id}/decide', [ApprovalController::class, 'decide'])->middleware(CheckPermission::class . ':approvals.decide')->name('approvals.decide');
            Route::post('/{id}/cancel', [ApprovalController::class, 'cancel'])->name('approvals.cancel');
        });
    });
});

// ══════════════════════════════════════════════════════════════
// Super-Admin Routes (platform-level, no workspace context)
// ══════════════════════════════════════════════════════════════
Route::prefix('admin')->middleware(['auth:sanctum', 'throttle:admin', SuperAdminMiddleware::class])->group(function () {
    // Dashboard
    Route::get('/dashboard',                           [SuperAdminController::class, 'dashboard'])->name('admin.dashboard');

    // Workspaces
    Route::get('/workspaces',                          [SuperAdminController::class, 'listWorkspaces'])->name('admin.workspaces.index');
    Route::get('/workspaces/{id}',                     [SuperAdminController::class, 'showWorkspace'])->name('admin.workspaces.show');
    Route::put('/workspaces/{id}/subscription',        [SuperAdminController::class, 'updateSubscription'])->name('admin.workspaces.subscription');
    Route::put('/workspaces/{id}/trial',               [SuperAdminController::class, 'updateTrial'])->name('admin.workspaces.trial');
    Route::put('/workspaces/{id}/status',              [SuperAdminController::class, 'updateWorkspaceStatus'])->name('admin.workspaces.status');
    Route::put('/workspaces/{id}/features',            [SuperAdminController::class, 'updateFeatures'])->name('admin.workspaces.features');
    Route::post('/workspaces/{id}/credits',            [SuperAdminController::class, 'adjustCredits'])->name('admin.workspaces.credits');

    // Plans
    Route::get('/plans',                               [SuperAdminController::class, 'listPlans'])->name('admin.plans.index');
    Route::post('/plans',                              [SuperAdminController::class, 'createPlan'])->name('admin.plans.create');
    Route::put('/plans/{id}',                          [SuperAdminController::class, 'updatePlan'])->name('admin.plans.update');
    Route::post('/plans/{id}/prices',                  [SuperAdminController::class, 'addPricing'])->name('admin.plans.pricing');

    // Settings
    Route::get('/settings',                            [SuperAdminController::class, 'getSettings'])->name('admin.settings.index');
    Route::put('/settings',                            [SuperAdminController::class, 'updateSettings'])->name('admin.settings.update');

    // Monitoring
    Route::get('/high-usage',                          [SuperAdminController::class, 'highUsage'])->name('admin.high-usage');

    // Billing management
    Route::post('/workspaces/{id}/setup-billing',      [SuperAdminController::class, 'setupBilling'])->name('admin.workspaces.setup-billing');
    Route::get('/workspaces/{id}/payments',             [SuperAdminController::class, 'paymentHistory'])->name('admin.workspaces.payments');

    // Manual payments
    Route::get('/manual-payments',                     [SuperAdminController::class, 'listManualPayments'])->name('admin.manual-payments.index');
    Route::post('/manual-payments/{id}/confirm',       [SuperAdminController::class, 'confirmManualPayment'])->name('admin.manual-payments.confirm');
    Route::post('/manual-payments/{id}/reject',        [SuperAdminController::class, 'rejectManualPayment'])->name('admin.manual-payments.reject');
});

// ══════════════════════════════════════════════════════════════
// Platform Admin Routes (activation codes, campaigns, workspace/user mgmt)
// ══════════════════════════════════════════════════════════════
Route::prefix('platform')->middleware(['auth:sanctum', 'throttle:admin', SuperAdminMiddleware::class])->group(function () {
    // Dashboard
    Route::get('/dashboard', [PlatformDashboardController::class, 'dashboard'])->name('platform.dashboard');

    // Workspaces
    Route::get('/workspaces',                  [PlatformWorkspaceController::class, 'index'])->name('platform.workspaces.index');
    Route::get('/workspaces/{id}',             [PlatformWorkspaceController::class, 'show'])->name('platform.workspaces.show');
    Route::put('/workspaces/{id}/status',      [PlatformWorkspaceController::class, 'updateStatus'])->name('platform.workspaces.status');
    Route::put('/workspaces/{id}/subscription', [PlatformWorkspaceController::class, 'updateSubscription'])->name('platform.workspaces.subscription');

    // Users
    Route::get('/users',                       [PlatformUserController::class, 'index'])->name('platform.users.index');
    Route::get('/users/{id}',                  [PlatformUserController::class, 'show'])->name('platform.users.show');
    Route::put('/users/{id}/platform-admin',   [PlatformUserController::class, 'updatePlatformAdmin'])->name('platform.users.admin');

    // Activation Campaigns
    Route::get('/activation-campaigns',        [PlatformActivationCampaignController::class, 'index'])->name('platform.campaigns.index');
    Route::post('/activation-campaigns',       [PlatformActivationCampaignController::class, 'store'])->name('platform.campaigns.store');
    Route::get('/activation-campaigns/{id}',   [PlatformActivationCampaignController::class, 'show'])->name('platform.campaigns.show');
    Route::put('/activation-campaigns/{id}',   [PlatformActivationCampaignController::class, 'update'])->name('platform.campaigns.update');
    Route::delete('/activation-campaigns/{id}', [PlatformActivationCampaignController::class, 'destroy'])->name('platform.campaigns.destroy');

    // Activation Codes
    Route::get('/activation-codes',                                  [PlatformActivationCodeController::class, 'index'])->name('platform.codes.index');
    Route::post('/activation-campaigns/{campaignId}/codes/generate', [PlatformActivationCodeController::class, 'generateBatch'])->name('platform.codes.generate');
    Route::get('/activation-codes/{id}',                             [PlatformActivationCodeController::class, 'show'])->name('platform.codes.show');
    Route::put('/activation-codes/{id}/status',                      [PlatformActivationCodeController::class, 'updateStatus'])->name('platform.codes.status');

    // System Health
    Route::get('/system-health', [PlatformSystemHealthController::class, 'health'])->name('platform.health');

    // AI Usage (Step 59.1)
    Route::get('/ai-usage',            [PlatformAiUsageController::class, 'summary'])->name('platform.ai-usage');
    Route::get('/ai-usage/workspaces', [PlatformAiUsageController::class, 'workspaces'])->name('platform.ai-usage.workspaces');
});

// ══════════════════════════════════════════════════════════════
// Webhooks (no authentication — signature-verified)
// ══════════════════════════════════════════════════════════════
Route::post('/webhooks/stripe', [WebhookController::class, 'handleStripe'])->name('webhooks.stripe');
