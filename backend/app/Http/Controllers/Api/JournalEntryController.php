<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreJournalEntryRequest;
use App\Http\Resources\JournalEntryResource;
use App\Services\JournalEntryService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class JournalEntryController extends Controller
{
    public function __construct(
        private readonly JournalEntryService $entries,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $result = $this->entries->list(
            $this->context->workspaceId(),
            $request->only(['status', 'per_page']),
        );
        return JournalEntryResource::collection($result);
    }

    public function show(string $id): JsonResponse
    {
        $entry = $this->entries->find($this->context->workspaceId(), $id);
        if (! $entry) {
            return response()->json(['message' => 'Journal entry not found.'], 404);
        }
        return response()->json(['data' => new JournalEntryResource($entry)]);
    }

    /**
     * Create journal entry with balanced lines.
     * Both service-level and DB-level validation enforce debit = credit.
     */
    public function store(StoreJournalEntryRequest $request): JsonResponse
    {
        try {
            $entry = $this->entries->create(
                $this->context->workspaceId(),
                $request->user()->id,
                $request->validated(),
            );
            return response()->json(['data' => new JournalEntryResource($entry)], 201);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * Update entry-level fields only (status, description).
     * Lines are immutable after creation.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $entry = $this->entries->find($this->context->workspaceId(), $id);
        if (! $entry) {
            return response()->json(['message' => 'Journal entry not found.'], 404);
        }

        $validated = $request->validate([
            'status'      => ['sometimes', 'string', 'in:draft,posted,reversed'],
            'description' => ['sometimes', 'string'],
            'reference'   => ['sometimes', 'nullable', 'string', 'max:100'],
        ]);

        $updated = $this->entries->update($entry, $validated);
        return response()->json(['data' => new JournalEntryResource($updated)]);
    }
}
