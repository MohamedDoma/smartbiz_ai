<?php

namespace App\Services;

use App\Models\Contact;
use App\Models\WorkspaceMembership;

/**
 * Centralized contact duplicate detection.
 *
 * Rules:
 * - Same workspace, same normalized non-empty phone → duplicate
 * - Same workspace, same normalized non-empty email → duplicate
 * - Names alone never trigger a duplicate
 *
 * Returns a result array with:
 *   'duplicate'   => bool
 *   'code'        => 'contact_duplicate' | 'contact_exists_outside_scope' | null
 *   'contact'     => Contact|null (only when visible to caller)
 *   'match_field' => 'phone' | 'email' | null
 */
class ContactDuplicateService
{
    /**
     * Normalize a phone number for comparison.
     * Strips whitespace, dashes, brackets, dots, plus signs.
     */
    public static function normalizePhone(?string $phone): string
    {
        if ($phone === null || trim($phone) === '') {
            return '';
        }
        // Remove all formatting characters
        return preg_replace('/[\s\-\(\)\.\+]/', '', trim($phone));
    }

    /**
     * Normalize an email for comparison.
     * Trim + lowercase.
     */
    public static function normalizeEmail(?string $email): string
    {
        if ($email === null || trim($email) === '') {
            return '';
        }
        return strtolower(trim($email));
    }

    /**
     * Check for a duplicate contact workspace-wide.
     *
     * @param  string                   $wsId        Workspace ID
     * @param  string|null              $phone       Raw phone
     * @param  string|null              $email       Raw email
     * @param  WorkspaceMembership|null $membership  Caller's membership (for scope)
     * @param  string|null              $excludeId   Existing contact ID to exclude (for updates)
     * @return array{duplicate: bool, code: string|null, contact: Contact|null, match_field: string|null}
     */
    public function check(
        string $wsId,
        ?string $phone,
        ?string $email,
        ?WorkspaceMembership $membership = null,
        ?string $excludeId = null,
    ): array {
        $normPhone = self::normalizePhone($phone);
        $normEmail = self::normalizeEmail($email);

        // Nothing to check
        if ($normPhone === '' && $normEmail === '') {
            return ['duplicate' => false, 'code' => null, 'contact' => null, 'match_field' => null];
        }

        // Build workspace-wide query (no scope — intentional for duplicate enforcement)
        $existing = null;
        $matchField = null;

        // Check phone first (most common unique identifier)
        if ($normPhone !== '') {
            $existing = $this->findByNormalizedPhone($wsId, $normPhone, $excludeId);
            if ($existing) {
                $matchField = 'phone';
            }
        }

        // Check email if no phone match
        if (! $existing && $normEmail !== '') {
            $existing = $this->findByNormalizedEmail($wsId, $normEmail, $excludeId);
            if ($existing) {
                $matchField = 'email';
            }
        }

        if (! $existing) {
            return ['duplicate' => false, 'code' => null, 'contact' => null, 'match_field' => null];
        }

        // Determine if the duplicate is visible to the caller
        if ($membership && ContactScope::canAccess($membership, $existing->assigned_membership_id)) {
            return [
                'duplicate'   => true,
                'code'        => 'contact_duplicate',
                'contact'     => $existing,
                'match_field' => $matchField,
            ];
        }

        // Duplicate exists but is outside the caller's scope
        return [
            'duplicate'   => true,
            'code'        => 'contact_exists_outside_scope',
            'contact'     => null,  // Do not expose
            'match_field' => null,
        ];
    }

    /**
     * Find a contact by normalized phone (database-filtered).
     */
    private function findByNormalizedPhone(string $wsId, string $normPhone, ?string $excludeId): ?Contact
    {
        // Use PostgreSQL regexp_replace for consistent server-side normalization
        return Contact::where('workspace_id', $wsId)
            ->when($excludeId, fn ($q) => $q->where('id', '!=', $excludeId))
            ->whereNotNull('phone')
            ->where('phone', '!=', '')
            ->whereRaw(
                "regexp_replace(trim(phone), '[\\s\\-\\(\\)\\.\\+]', '', 'g') = ?",
                [$normPhone]
            )
            ->first();
    }

    /**
     * Find a contact by normalized email (database-filtered).
     */
    private function findByNormalizedEmail(string $wsId, string $normEmail, ?string $excludeId): ?Contact
    {
        return Contact::where('workspace_id', $wsId)
            ->when($excludeId, fn ($q) => $q->where('id', '!=', $excludeId))
            ->whereNotNull('email')
            ->where('email', '!=', '')
            ->whereRaw('lower(trim(email)) = ?', [$normEmail])
            ->first();
    }
}
