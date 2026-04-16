<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StorePaymentRequest;
use App\Http\Resources\PaymentResource;
use App\Services\PaymentService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class PaymentController extends Controller
{
    public function __construct(
        private readonly PaymentService $payments,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return PaymentResource::collection(
            $this->payments->list($this->context->workspaceId(), $request->only(['invoice_id', 'status', 'per_page']))
        );
    }

    public function show(string $id): JsonResponse
    {
        $p = $this->payments->find($this->context->workspaceId(), $id);
        if (! $p) return response()->json(['message' => 'Payment not found.'], 404);
        return response()->json(['data' => new PaymentResource($p)]);
    }

    public function store(StorePaymentRequest $request): JsonResponse
    {
        $payment = $this->payments->create(
            $this->context->workspaceId(),
            $request->user()->id,
            $request->validated(),
        );
        return response()->json(['data' => new PaymentResource($payment)], 201);
    }

    /**
     * Reverse a payment.
     */
    public function reverse(Request $request, string $id): JsonResponse
    {
        $payment = $this->payments->find($this->context->workspaceId(), $id);
        if (! $payment) return response()->json(['message' => 'Payment not found.'], 404);

        $data = $request->validate(['reason' => ['required', 'string']]);

        try {
            $reversal = $this->payments->reverse(
                $this->context->workspaceId(),
                $request->user()->id,
                $payment,
                $data['reason'],
            );
            return response()->json(['data' => new PaymentResource($reversal)], 201);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }
}
