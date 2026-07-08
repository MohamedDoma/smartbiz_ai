<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ReportCatalogService;
use Illuminate\Http\JsonResponse;

class ReportCatalogController extends Controller
{
    public function index(): JsonResponse
    {
        $svc = new ReportCatalogService();
        $catalog = $svc->getCatalog();

        $list = [];
        foreach ($catalog as $key => $ds) {
            $list[] = [
                'key'          => $key,
                'display_name' => $ds['display_name'],
                'column_count' => count($ds['columns']),
                'filter_count' => count($ds['filters']),
            ];
        }

        return response()->json(['data' => $list]);
    }

    public function show(string $dataSource): JsonResponse
    {
        $svc = new ReportCatalogService();
        $ds = $svc->getDataSource($dataSource);

        if (!$ds) {
            return response()->json(['message' => 'Unknown data source.'], 422);
        }

        return response()->json(['data' => $ds]);
    }
}
