<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ReportingService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;

class ReportingController extends Controller
{
    public function __construct(
        private readonly ReportingService $reporting,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function salesSummary(): JsonResponse
    {
        return response()->json([
            'data' => $this->reporting->salesSummary($this->context->workspaceId()),
        ]);
    }

    public function invoicePaymentSummary(): JsonResponse
    {
        return response()->json([
            'data' => $this->reporting->invoicePaymentSummary($this->context->workspaceId()),
        ]);
    }

    public function inventorySummary(): JsonResponse
    {
        return response()->json([
            'data' => $this->reporting->inventorySummary($this->context->workspaceId()),
        ]);
    }

    public function accountBalances(): JsonResponse
    {
        return response()->json([
            'data' => $this->reporting->accountBalances($this->context->workspaceId()),
        ]);
    }

    public function receivablePayable(): JsonResponse
    {
        return response()->json([
            'data' => $this->reporting->receivablePayable($this->context->workspaceId()),
        ]);
    }
}
