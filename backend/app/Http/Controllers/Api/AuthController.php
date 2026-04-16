<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Resources\MembershipResource;
use App\Http\Resources\UserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    /**
     * POST /api/auth/login
     *
     * Authenticates via email + password_hash, returns a Sanctum API token.
     */
    public function login(LoginRequest $request): JsonResponse
    {
        $validated = $request->validated();

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password_hash)) {
            return response()->json([
                'message' => 'Invalid credentials.',
            ], 401);
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => 'Account is deactivated.',
            ], 403);
        }

        // Create Sanctum token — name identifies the device/session.
        $token = $user->createToken(
            name: 'api',
            expiresAt: now()->addHours(24),
        );

        return response()->json([
            'token' => $token->plainTextToken,
            'user'  => new UserResource($user),
        ]);
    }

    /**
     * POST /api/auth/logout
     *
     * Revokes the current Sanctum token.
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out.',
        ]);
    }

    /**
     * GET /api/auth/me
     *
     * Returns the authenticated user with their workspace memberships.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        $memberships = $user->activeMemberships()
            ->with(['workspace', 'membershipRoles.role'])
            ->get();

        return response()->json([
            'user'        => new UserResource($user),
            'memberships' => MembershipResource::collection($memberships),
        ]);
    }
}
