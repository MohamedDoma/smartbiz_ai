<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        api: __DIR__.'/../routes/api.php',
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->statefulApi();
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Unique constraint violations (duplicate SKU, invoice_number, etc.)
        $exceptions->renderable(function (\Illuminate\Database\QueryException $e) {
            if (str_contains($e->getMessage(), '23505') || str_contains($e->getMessage(), 'unique')) {
                // Extract the constraint name for a meaningful message
                preg_match('/constraint "([^"]+)"/', $e->getMessage(), $m);
                $constraint = $m[1] ?? 'unknown';
                return response()->json([
                    'message' => 'A record with this value already exists.',
                    'error'   => 'duplicate_entry',
                    'constraint' => $constraint,
                ], 409);
            }

            // Check constraint violations (invalid type, negative amounts, etc.)
            if (str_contains($e->getMessage(), '23514') || str_contains($e->getMessage(), 'check')) {
                preg_match('/constraint "([^"]+)"/', $e->getMessage(), $m);
                return response()->json([
                    'message' => 'Data violates a business rule.',
                    'error'   => 'check_violation',
                    'constraint' => $m[1] ?? 'unknown',
                ], 422);
            }

            // Workspace isolation trigger violations
            if (str_contains($e->getMessage(), 'Workspace isolation violation') || str_contains($e->getMessage(), 'workspace')) {
                return response()->json([
                    'message' => 'Workspace isolation violation: the referenced record does not belong to this workspace.',
                    'error'   => 'workspace_isolation',
                ], 403);
            }

            // Unbalanced journal entry (deferred trigger)
            if (str_contains($e->getMessage(), 'unbalanced') || str_contains($e->getMessage(), 'غير متوازن')) {
                return response()->json([
                    'message' => 'Journal entry is unbalanced: total debits must equal total credits.',
                    'error'   => 'journal_unbalanced',
                ], 422);
            }

            // Don't expose raw DB errors in production
            if (! config('app.debug')) {
                return response()->json([
                    'message' => 'A database error occurred.',
                    'error'   => 'database_error',
                ], 500);
            }
        });

        // Custom workspace/permission exceptions
        $exceptions->renderable(function (\App\Exceptions\WorkspaceRequiredException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'workspace_required'], 400);
        });
        $exceptions->renderable(function (\App\Exceptions\WorkspaceAccessDeniedException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'workspace_access_denied'], 403);
        });
        $exceptions->renderable(function (\App\Exceptions\PermissionDeniedException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'permission_denied'], 403);
        });

        // Insufficient stock
        $exceptions->renderable(function (\App\Exceptions\InsufficientStockException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'insufficient_stock'], 422);
        });

        // Model not found
        $exceptions->renderable(function (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            return response()->json(['message' => 'Resource not found.', 'error' => 'not_found'], 404);
        });
    })->create();
