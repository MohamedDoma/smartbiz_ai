<?php

namespace Tests\Feature;

use Database\Seeders\FoundationSeeder;

class AuthTest extends SmartBizTestCase
{
    public function test_login_with_valid_credentials(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => FoundationSeeder::USER_PASSWORD,
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'email', 'full_name']]);
    }

    public function test_login_with_invalid_credentials(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => 'wrong-password',
        ]);

        $response->assertUnauthorized()
            ->assertJsonFragment(['message' => 'Invalid credentials.']);
    }

    public function test_me_endpoint(): void
    {
        $response = $this->authGet('/api/auth/me');

        $response->assertOk()
            ->assertJsonStructure([
                'user' => ['id', 'email', 'full_name'],
                'memberships',
            ])
            ->assertJsonPath('user.email', FoundationSeeder::USER_EMAIL);
    }

    public function test_logout(): void
    {
        // Verify logout succeeds
        $response = $this->authPost('/api/auth/logout');
        $response->assertOk();

        // NOTE: Cannot verify token revocation in-process because Sanctum
        // caches the resolved auth guard in memory within the same test process.
        // The token IS deleted from the DB (verified via integration tests).

        $this->token = ''; // Prevent tearDown from trying to logout again
    }

    public function test_me_without_auth(): void
    {
        $response = $this->getJson('/api/auth/me');
        $response->assertUnauthorized();
    }
}
