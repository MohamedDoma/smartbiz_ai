<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AuditLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BomController;
use App\Http\Controllers\Api\ContactController;
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

Route::post('/auth/login', [AuthController::class, 'login'])
    ->name('auth.login');

// ── Authenticated (no workspace required) ───────────────────────

Route::middleware('auth:sanctum')->group(function () {

    Route::post('/auth/logout', [AuthController::class, 'logout'])
        ->name('auth.logout');

    Route::get('/auth/me', [AuthController::class, 'me'])
        ->name('auth.me');

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
    });
});
