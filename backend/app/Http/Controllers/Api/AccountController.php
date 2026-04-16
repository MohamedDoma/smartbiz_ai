<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreAccountRequest;
use App\Http\Resources\AccountResource;
use App\Services\AccountService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;

class AccountController extends Controller
{
    public function __construct(
        private readonly AccountService $accounts,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * List root accounts with children (tree).
     */
    public function index(): JsonResponse
    {
        $tree = $this->accounts->list($this->context->workspaceId());
        return response()->json(['data' => AccountResource::collection($tree)]);
    }

    public function show(string $id): JsonResponse
    {
        $account = $this->accounts->find($this->context->workspaceId(), $id);
        if (! $account) {
            return response()->json(['message' => 'Account not found.'], 404);
        }
        return response()->json(['data' => new AccountResource($account)]);
    }

    public function store(StoreAccountRequest $request): JsonResponse
    {
        $account = $this->accounts->create(
            $this->context->workspaceId(),
            $request->validated(),
        );
        return response()->json(['data' => new AccountResource($account)], 201);
    }

    public function update(StoreAccountRequest $request, string $id): JsonResponse
    {
        $account = $this->accounts->find($this->context->workspaceId(), $id);
        if (! $account) {
            return response()->json(['message' => 'Account not found.'], 404);
        }
        $updated = $this->accounts->update($account, $request->validated());
        return response()->json(['data' => new AccountResource($updated)]);
    }

    public function destroy(string $id): JsonResponse
    {
        $account = $this->accounts->find($this->context->workspaceId(), $id);
        if (! $account) {
            return response()->json(['message' => 'Account not found.'], 404);
        }
        $this->accounts->delete($account);
        return response()->json(['message' => 'Account deleted.']);
    }
}
