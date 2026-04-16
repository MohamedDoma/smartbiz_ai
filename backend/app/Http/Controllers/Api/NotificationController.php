<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\NotificationResource;
use App\Models\Notification;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function __construct(private readonly WorkspaceContextManager $context) {}

    public function index(Request $request): JsonResponse
    {
        $query = Notification::where('workspace_id', $this->context->workspaceId())
            ->where('user_id', $request->user()->id);

        if ($request->has('is_read')) {
            $query->where('is_read', filter_var($request->input('is_read'), FILTER_VALIDATE_BOOLEAN));
        }

        $notifications = $query->orderByDesc('created_at')
            ->paginate($request->input('per_page', 25));

        return response()->json([
            'data' => NotificationResource::collection($notifications),
            'meta' => [
                'current_page' => $notifications->currentPage(),
                'total'        => $notifications->total(),
                'per_page'     => $notifications->perPage(),
                'unread_count' => Notification::where('workspace_id', $this->context->workspaceId())
                    ->where('user_id', $request->user()->id)
                    ->where('is_read', false)
                    ->count(),
            ],
        ]);
    }

    public function markRead(string $id): JsonResponse
    {
        $n = Notification::where('workspace_id', $this->context->workspaceId())->find($id);
        if (! $n) return response()->json(['message' => 'Notification not found.'], 404);
        $n->update(['is_read' => true]);
        return response()->json(['data' => new NotificationResource($n->fresh())]);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $count = Notification::where('workspace_id', $this->context->workspaceId())
            ->where('user_id', $request->user()->id)
            ->where('is_read', false)
            ->update(['is_read' => true]);
        return response()->json(['message' => "{$count} notifications marked as read."]);
    }
}
