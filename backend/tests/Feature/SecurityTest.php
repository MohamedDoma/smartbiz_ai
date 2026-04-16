<?php

namespace Tests\Feature;

use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;

/**
 * Batch 3, Part B — Security Boundary Tests (S01–S07).
 *
 * Tests authentication, token lifecycle, header forgery, and membership enforcement.
 */
class SecurityTest extends SmartBizTestCase
{
    /** S01 — Login with wrong password → 401 */
    public function test_s01_login_wrong_password(): void
    {
        $this->postJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => 'WrongPassword123!',
        ])->assertUnauthorized();
    }

    /** S02 — Login with non-existent email → 401 */
    public function test_s02_login_nonexistent_email(): void
    {
        $this->postJson('/api/auth/login', [
            'email'    => 'doesnotexist@example.com',
            'password' => 'AnyPassword123!',
        ])->assertUnauthorized();
    }

    /** S03 — /me without token → 401 */
    public function test_s03_me_without_token(): void
    {
        $this->getJson('/api/auth/me')->assertUnauthorized();
    }

    /** S04 — Token revoked after logout → 401 */
    public function test_s04_revoked_token_after_logout(): void
    {
        // Login fresh (separate from setUp token)
        $login = $this->postJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => FoundationSeeder::USER_PASSWORD,
        ]);
        $login->assertOk();
        $freshToken = $login->json('token');

        // Verify token works first
        $this->withHeaders([
            'Authorization' => "Bearer {$freshToken}",
            'Accept'        => 'application/json',
        ])->getJson('/api/auth/me')->assertOk();

        // Logout (deletes token from DB)
        $this->withHeaders([
            'Authorization' => "Bearer {$freshToken}",
            'Accept'        => 'application/json',
        ])->postJson('/api/auth/logout')->assertOk();

        // Reset application state to prevent cached auth
        $this->refreshApplication();

        // Use the revoked token — must fail
        $this->withHeaders([
            'Authorization' => "Bearer {$freshToken}",
            'Accept'        => 'application/json',
        ])->getJson('/api/auth/me')->assertUnauthorized();
    }

    /** S05 — Login with empty payload → 422 */
    public function test_s05_login_empty_payload(): void
    {
        $this->postJson('/api/auth/login', [])
            ->assertUnprocessable();
    }

    /** S06 — PUT to a POST-only endpoint → 405 */
    public function test_s06_put_to_post_only_endpoint(): void
    {
        $response = $this->withHeaders([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ])->putJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => FoundationSeeder::USER_PASSWORD,
        ]);
        $response->assertMethodNotAllowed();
    }

    /** S07 — Access workspace endpoint without WS membership → 403 */
    public function test_s07_access_without_workspace_membership(): void
    {
        // WS-B admin has NO membership in WS-A
        $token = $this->postJson('/api/auth/login', [
            'email'    => 'b_admin@cert.test',
            'password' => CertificationSeeder::PASSWORD,
        ])->json('token');

        $this->withHeaders([
            'Authorization'  => "Bearer {$token}",
            'X-Workspace-Id' => CertificationSeeder::WS_A, // WS-A — no membership
            'Accept'         => 'application/json',
        ])->getJson('/api/contacts')->assertForbidden();
    }
}
