<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\RecurringExpenseResource;
use App\Services\RecurringExpenseService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class RecurringExpenseController extends Controller
{
    public function __construct(
        private readonly RecurringExpenseService $expenses,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return RecurringExpenseResource::collection(
            $this->expenses->list($this->context->workspaceId(), $request->only(['is_active', 'per_page']))
        );
    }

    public function show(string $id): JsonResponse
    {
        $e = $this->expenses->find($this->context->workspaceId(), $id);
        if (! $e) return response()->json(['message' => 'Recurring expense not found.'], 404);
        return response()->json(['data' => new RecurringExpenseResource($e)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'category'      => ['required', 'string', 'max:100'],
            'amount'        => ['required', 'numeric', 'gt:0'],
            'frequency'     => ['required', 'in:daily,weekly,monthly,quarterly,semi_annual,annual'],
            'next_due_date' => ['required', 'date'],
        ]);
        $e = $this->expenses->create($this->context->workspaceId(), $data);
        return response()->json(['data' => new RecurringExpenseResource($e)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $e = $this->expenses->find($this->context->workspaceId(), $id);
        if (! $e) return response()->json(['message' => 'Recurring expense not found.'], 404);
        $data = $request->validate([
            'category'      => ['sometimes', 'string', 'max:100'],
            'amount'        => ['sometimes', 'numeric', 'gt:0'],
            'frequency'     => ['sometimes', 'in:daily,weekly,monthly,quarterly,semi_annual,annual'],
            'next_due_date' => ['sometimes', 'date'],
            'is_active'     => ['sometimes', 'boolean'],
        ]);
        $updated = $this->expenses->update($e, $data);
        return response()->json(['data' => new RecurringExpenseResource($updated)]);
    }

    public function destroy(string $id): JsonResponse
    {
        $e = $this->expenses->find($this->context->workspaceId(), $id);
        if (! $e) return response()->json(['message' => 'Recurring expense not found.'], 404);
        $this->expenses->delete($e);
        return response()->json(['message' => 'Recurring expense deleted.']);
    }
}
