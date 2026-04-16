<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\AuditLogResource;
use App\Models\AuditLog;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuditLogController extends Controller
{
    public function __construct(private readonly WorkspaceContextManager $context) {}

    public function index(Request $request): JsonResponse
    {
        $query = AuditLog::where('workspace_id', $this->context->workspaceId());

        if ($request->has('entity_type')) {
            $query->where('entity_type', $request->input('entity_type'));
        }
        if ($request->has('entity_id')) {
            $query->where('entity_id', $request->input('entity_id'));
        }
        if ($request->has('user_id')) {
            $query->where('user_id', $request->input('user_id'));
        }

        $logs = $query->orderByDesc('created_at')
            ->paginate($request->input('per_page', 25));

        return response()->json([
            'data' => AuditLogResource::collection($logs),
            'meta' => [
                'current_page' => $logs->currentPage(),
                'total'        => $logs->total(),
                'per_page'     => $logs->perPage(),
            ],
        ]);
    }

    public function show(string $id): JsonResponse
    {
        $log = AuditLog::where('workspace_id', $this->context->workspaceId())->find($id);
        if (! $log) return response()->json(['message' => 'Audit log not found.'], 404);
        return response()->json(['data' => new AuditLogResource($log)]);
    }
}
