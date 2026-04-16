<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreInvoiceRequest;
use App\Http\Resources\InvoiceResource;
use App\Services\InvoiceService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class InvoiceController extends Controller
{
    public function __construct(
        private readonly InvoiceService $invoices,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $result = $this->invoices->list(
            $this->context->workspaceId(),
            $request->only(['payment_status', 'invoice_type', 'contact_id', 'per_page']),
        );
        return InvoiceResource::collection($result);
    }

    /**
     * Show invoice with items — child-table access done via parent relationship.
     */
    public function show(string $id): JsonResponse
    {
        $invoice = $this->invoices->find($this->context->workspaceId(), $id);
        if (! $invoice) {
            return response()->json(['message' => 'Invoice not found.'], 404);
        }
        return response()->json(['data' => new InvoiceResource($invoice)]);
    }

    /**
     * Create invoice with items in a single transaction.
     */
    public function store(StoreInvoiceRequest $request): JsonResponse
    {
        $invoice = $this->invoices->create(
            $this->context->workspaceId(),
            $request->user()->id,
            $request->validated(),
        );
        return response()->json(['data' => new InvoiceResource($invoice)], 201);
    }

    /**
     * Update invoice-level fields only (payment_status, due_date, etc).
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $invoice = $this->invoices->find($this->context->workspaceId(), $id);
        if (! $invoice) {
            return response()->json(['message' => 'Invoice not found.'], 404);
        }

        $validated = $request->validate([
            'payment_status' => ['sometimes', 'string', 'in:unpaid,partial,paid,overdue,refunded'],
            'due_date'       => ['sometimes', 'nullable', 'date'],
            'invoice_number' => ['sometimes', 'nullable', 'string', 'max:100'],
        ]);

        $updated = $this->invoices->update($invoice, $validated);
        return response()->json(['data' => new InvoiceResource($updated)]);
    }
}
