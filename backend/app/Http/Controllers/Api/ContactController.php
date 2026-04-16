<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreContactRequest;
use App\Http\Requests\UpdateContactRequest;
use App\Http\Resources\ContactResource;
use App\Services\ContactService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ContactController extends Controller
{
    public function __construct(
        private readonly ContactService $contacts,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * GET /api/contacts
     *
     * List contacts with optional filtering.
     * Query params: type, search, per_page.
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $result = $this->contacts->list(
            $this->context->workspaceId(),
            $request->only(['type', 'search', 'per_page']),
        );

        return ContactResource::collection($result);
    }

    /**
     * GET /api/contacts/{id}
     */
    public function show(string $id): JsonResponse
    {
        $contact = $this->contacts->find($this->context->workspaceId(), $id);

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        return response()->json([
            'data' => new ContactResource($contact),
        ]);
    }

    /**
     * POST /api/contacts
     */
    public function store(StoreContactRequest $request): JsonResponse
    {
        $contact = $this->contacts->create(
            $this->context->workspaceId(),
            $request->validated(),
        );

        return response()->json([
            'data' => new ContactResource($contact),
        ], 201);
    }

    /**
     * PUT /api/contacts/{id}
     */
    public function update(UpdateContactRequest $request, string $id): JsonResponse
    {
        $contact = $this->contacts->find($this->context->workspaceId(), $id);

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        $updated = $this->contacts->update($contact, $request->validated());

        return response()->json([
            'data' => new ContactResource($updated),
        ]);
    }

    /**
     * DELETE /api/contacts/{id}
     */
    public function destroy(string $id): JsonResponse
    {
        $contact = $this->contacts->find($this->context->workspaceId(), $id);

        if (! $contact) {
            return response()->json(['message' => 'Contact not found.'], 404);
        }

        $this->contacts->delete($contact);

        return response()->json(['message' => 'Contact deleted.']);
    }
}
