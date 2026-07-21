<?php

namespace Tests\Feature;

use Database\Seeders\FoundationSeeder;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Base class for SmartBiz API integration tests.
 *
 * Uses the isolated smartbiz_test PostgreSQL database. Every test runs inside
 * a transaction that is rolled back automatically.
 *
 * Run backend/scripts/prepare-test-database.sh before the suite to rebuild and
 * seed the test database. Never point this suite at the development database.
 */
abstract class SmartBizTestCase extends TestCase
{
    use DatabaseTransactions;
    protected string $token = '';
    protected string $workspaceId = FoundationSeeder::WORKSPACE_ID;

    protected function setUp(): void
    {
        parent::setUp();

        // Ensure we're using PostgreSQL (not SQLite)
        $this->assertEquals('pgsql', config('database.default'),
            'Tests must run against PostgreSQL, not SQLite.');

        // Login as the seeded admin user to get an auth token
        $response = $this->postJson('/api/auth/login', [
            'email'    => FoundationSeeder::USER_EMAIL,
            'password' => FoundationSeeder::USER_PASSWORD,
        ]);
        $response->assertOk();
        $this->token = $response->json('token');
    }

    /**
     * Make an authenticated, workspace-scoped request.
     */
    protected function wsGet(string $uri, array $headers = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders(array_merge([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ], $headers))->getJson($uri);
    }

    protected function wsPost(string $uri, array $data = [], array $headers = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders(array_merge([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ], $headers))->postJson($uri, $data);
    }

    protected function wsPut(string $uri, array $data = [], array $headers = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders(array_merge([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ], $headers))->putJson($uri, $data);
    }

    protected function wsDelete(string $uri, array $headers = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders(array_merge([
            'Authorization'  => "Bearer {$this->token}",
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ], $headers))->deleteJson($uri);
    }

    protected function authGet(string $uri): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->getJson($uri);
    }

    protected function authPost(string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->postJson($uri, $data);
    }

    protected function tearDown(): void
    {
        // Revoke any test tokens to prevent accumulation
        if ($this->token) {
            $this->authPost('/api/auth/logout');
        }
        parent::tearDown();
    }
}
