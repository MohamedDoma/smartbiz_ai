<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreStockReservationRequest;
use App\Http\Resources\StockReservationResource;
use App\Services\StockReservationService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class StockReservationController extends Controller
{
    public function __construct(
        private readonly StockReservationService $reservations,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return StockReservationResource::collection(
            $this->reservations->list($this->context->workspaceId(), $request->only(['status', 'order_id', 'product_id', 'warehouse_id', 'per_page']))
        );
    }

    public function show(string $id): JsonResponse
    {
        $r = $this->reservations->find($this->context->workspaceId(), $id);
        if (! $r) return response()->json(['message' => 'Reservation not found.'], 404);
        return response()->json(['data' => new StockReservationResource($r)]);
    }

    public function store(StoreStockReservationRequest $request): JsonResponse
    {
        $reservation = $this->reservations->create(
            $this->context->workspaceId(),
            $request->validated(),
        );
        return response()->json(['data' => new StockReservationResource($reservation)], 201);
    }

    public function release(string $id): JsonResponse
    {
        $r = $this->reservations->find($this->context->workspaceId(), $id);
        if (! $r) return response()->json(['message' => 'Reservation not found.'], 404);

        try {
            $released = $this->reservations->release($r);
            return response()->json(['data' => new StockReservationResource($released)]);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    public function fulfill(Request $request, string $id): JsonResponse
    {
        $r = $this->reservations->find($this->context->workspaceId(), $id);
        if (! $r) return response()->json(['message' => 'Reservation not found.'], 404);

        $data = $request->validate(['quantity' => ['required', 'numeric', 'gt:0']]);

        try {
            $fulfilled = $this->reservations->fulfill($r, $data['quantity']);
            return response()->json(['data' => new StockReservationResource($fulfilled)]);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }
}
