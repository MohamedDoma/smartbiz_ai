<?php

namespace App\Services\Ai;

use App\Models\WorkspaceMembership;
use App\Services\PermissionResolver;

/**
 * Step 59.2 — AI Tool Permission Guard.
 *
 * Checks whether a user has the required permission to execute an AI tool.
 * Uses the same PermissionResolver as the rest of the application.
 * Security boundary: the LLM prompt is never trusted for authorization.
 */
class AiToolPermissionGuard
{
    public function __construct(
        private readonly PermissionResolver $resolver,
    ) {}

    /**
     * Check if the user can execute a tool.
     *
     * Step 59.2.1 security order:
     * 1. A valid membership must exist.
     * 2. The membership must be active.
     * 3. Tools with null permission are allowed for active members.
     * 4. Tools with a required permission go through PermissionResolver.
     *
     * @return array{allowed: bool, reason: string|null}
     */
    public function check(
        ?WorkspaceMembership $membership,
        ?string $requiredPermission,
    ): array {
        // Step 1+2: Active membership is always required
        if ($membership === null) {
            return [
                'allowed' => false,
                'reason'  => 'لا توجد عضوية فعّالة في مساحة العمل الحالية.',
            ];
        }

        if ($membership->status !== 'active') {
            return [
                'allowed' => false,
                'reason'  => 'عضويتك في مساحة العمل غير نشطة.',
            ];
        }

        // Step 3: No module permission required = allowed for any active member
        if ($requiredPermission === null || $requiredPermission === '') {
            return ['allowed' => true, 'reason' => null];
        }

        // Step 4: Check module permission via the standard resolver
        if ($this->resolver->can($membership, $requiredPermission)) {
            return ['allowed' => true, 'reason' => null];
        }

        return [
            'allowed' => false,
            'reason'  => 'لا أستطيع عرض هذه المعلومة لأنها خارج صلاحياتك.',
        ];
    }
}
