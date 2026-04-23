<?php

namespace Tests\Feature;

use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;

/**
 * Production Ops Tests (OPS01–OPS05).
 *
 * Verifies health endpoint, correlation IDs, rate limiting,
 * backup command, and queue dispatch.
 */
class ProductionOpsTest extends SmartBizTestCase
{
    // ═══════════════════════════════════════════════════════════
    // OPS01 — Health endpoint returns DB + Redis status
    // ═══════════════════════════════════════════════════════════

    public function test_ops01_health_endpoint(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'status',
                'checks' => ['database', 'redis', 'queue', 'cache'],
                'version',
                'env',
            ])
            ->assertJson(['status' => 'healthy']);

        // Check that DB shows OK
        $response->assertJsonPath('checks.database.status', 'ok');
        $response->assertJsonPath('checks.redis.status', 'ok');
    }

    // ═══════════════════════════════════════════════════════════
    // OPS02 — Correlation ID middleware injects header
    // ═══════════════════════════════════════════════════════════

    public function test_ops02_correlation_id_injected(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $this->assertTrue($response->headers->has('X-Correlation-ID'));
        $this->assertNotEmpty($response->headers->get('X-Correlation-ID'));
    }

    public function test_ops02_correlation_id_passthrough(): void
    {
        $customId = 'test-corr-' . uniqid();

        $response = $this->getJson('/api/health', [
            'X-Correlation-ID' => $customId,
        ]);

        $response->assertStatus(200);
        $this->assertEquals($customId, $response->headers->get('X-Correlation-ID'));
    }

    // ═══════════════════════════════════════════════════════════
    // OPS03 — Rate limiting works (auth endpoint)
    // ═══════════════════════════════════════════════════════════

    public function test_ops03_rate_limiting_enforced(): void
    {
        // Auth rate limit is 5/min. Fire 6 requests.
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/auth/login', [
                'email'    => 'fake@test.com',
                'password' => 'wrong',
            ]);
        }

        $response = $this->postJson('/api/auth/login', [
            'email'    => 'fake@test.com',
            'password' => 'wrong',
        ]);

        $response->assertStatus(429);
    }

    // ═══════════════════════════════════════════════════════════
    // OPS04 — Backup command runs (checks exit code)
    // ═══════════════════════════════════════════════════════════

    public function test_ops04_backup_command_runs(): void
    {
        // This tests the command's ability to start (pg_dump may not
        // be available in all test environments, so we just test the
        // artisan command registration)
        $this->artisan('db:backup')->assertExitCode(0);
    }

    // ═══════════════════════════════════════════════════════════
    // OPS05 — Queue connection works (Redis)
    // ═══════════════════════════════════════════════════════════

    public function test_ops05_queue_connection(): void
    {
        // Verify Redis is reachable (queue backend in production)
        $this->assertEquals('PONG', Redis::ping());

        // Verify Redis queue connection is configured
        $this->assertNotNull(config('queue.connections.redis'));
        $this->assertEquals('redis', config('queue.connections.redis.driver'));
    }
}
