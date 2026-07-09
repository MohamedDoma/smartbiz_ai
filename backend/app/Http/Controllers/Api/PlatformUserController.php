<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PlatformUserController extends Controller
{
    public function index(): JsonResponse
    {
        $users = User::orderByDesc('created_at')
            ->get()
            ->map(fn ($u) => $this->fmt($u));

        return response()->json(['data' => $users]);
    }

    public function show(string $id): JsonResponse
    {
        $user = User::findOrFail($id);
        return response()->json(['data' => $this->fmt($user)]);
    }

    public function updatePlatformAdmin(Request $request, string $id): JsonResponse
    {
        $v = $request->validate([
            'is_super_admin' => 'required|boolean',
        ]);

        $user = User::findOrFail($id);

        // Prevent demoting yourself
        if ($request->user()->id === $id && !$v['is_super_admin']) {
            return response()->json(['message' => 'Cannot remove your own platform admin access.'], 422);
        }

        $user->update(['is_super_admin' => $v['is_super_admin']]);

        return response()->json(['data' => $this->fmt($user->fresh())]);
    }

    private function fmt(User $u): array
    {
        return [
            'id'             => $u->id,
            'full_name'      => $u->full_name,
            'email'          => $u->email,
            'phone_number'   => $u->phone_number,
            'is_active'      => $u->is_active,
            'is_super_admin' => $u->is_super_admin,
            'preferred_locale' => $u->preferred_locale,
            'created_at'     => $u->created_at?->toIso8601String(),
        ];
    }
}
