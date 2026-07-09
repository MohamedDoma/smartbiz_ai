<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\PlatformDashboardService;
use Illuminate\Http\JsonResponse;

class PlatformDashboardController extends Controller
{
    public function dashboard(): JsonResponse
    {
        $stats = (new PlatformDashboardService())->getStats();
        return response()->json(['data' => $stats]);
    }
}
