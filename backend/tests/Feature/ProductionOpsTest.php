<?php

namespace Tests\Feature;

use App\Jobs\QueueHeartbeatJob;
use App\Services\Operations\OperationalHealthService;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Redis;

/**
 * Production Ops Tests (OPS01–OPS07).
 *
 * Verifies public health privacy, correlation IDs, rate limiting,
 * verified backups, operational diagnostics, queue heartbeat, and queue config.
 */
class ProductionOpsTest extends SmartBizTestCase
{
    public function test_ops01_health_endpoint_is_minimal_and_healthy(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200)
            ->assertJsonStructure(['status', 'version', 'checked_at'])
            ->assertJson(['status' => 'healthy']);

        $payload = $response->json();
        $this->assertArrayNotHasKey('checks', $payload);
        $this->assertArrayNotHasKey('env', $payload);
    }

    public function test_ops02_correlation_id_injected(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $this->assertTrue($response->headers->has('X-Correlation-ID'));
        $this->assertNotEmpty($response->headers->get('X-Correlation-ID'));
    }

    public function test_ops02_correlation_id_passthrough(): void
    {
        $customId = 'test-corr-'.uniqid();

        $response = $this->getJson('/api/health', [
            'X-Correlation-ID' => $customId,
        ]);

        $response->assertStatus(200);
        $this->assertEquals($customId, $response->headers->get('X-Correlation-ID'));
    }

    public function test_ops03_rate_limiting_enforced(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/auth/login', [
                'email' => 'fake@test.com',
                'password' => 'wrong',
            ]);
        }

        $response = $this->postJson('/api/auth/login', [
            'email' => 'fake@test.com',
            'password' => 'wrong',
        ]);

        $response->assertStatus(429);
    }

    public function test_ops04_backup_command_writes_verified_archive_and_metadata(): void
    {
        $directory = storage_path('framework/testing/ops-backups');
        File::deleteDirectory($directory);

        config([
            'operations.backup.path' => $directory,
            'operations.backup.minimum_free_mb' => 0,
            'operations.backup.mirror_disk' => null,
        ]);

        $this->artisan('db:backup --retention=1')->assertExitCode(0);

        $archives = glob($directory.'/smartbiz_db_*.dump') ?: [];
        $this->assertCount(1, $archives);
        $this->assertFileExists($archives[0].'.sha256');
        $this->assertFileExists($archives[0].'.json');

        $metadata = json_decode((string) file_get_contents($archives[0].'.json'), true, flags: JSON_THROW_ON_ERROR);
        $this->assertSame('database', $metadata['type']);
        $this->assertSame(hash_file('sha256', $archives[0]), $metadata['sha256']);
    }

    public function test_ops05_operational_check_command_runs(): void
    {
        $this->mock(OperationalHealthService::class, function ($mock): void {
            $mock->shouldReceive('diagnostics')
                ->once()
                ->andReturn([
                    'status' => 'healthy',
                    'version' => '1.0.0',
                    'checked_at' => '2026-01-01T00:00:00+00:00',
                    'checks' => [
                        'database' => ['status' => 'ok'],
                        'redis' => ['status' => 'ok'],
                        'cache' => ['status' => 'ok'],
                    ],
                ]);
        });

        $this->artisan('ops:check --json')->assertExitCode(0);
    }

    public function test_ops06_queue_heartbeat_records_processed_timestamp(): void
    {
        Cache::forget('ops:queue:last_processed_at');

        (new QueueHeartbeatJob)->handle();

        $this->assertNotEmpty(Cache::get('ops:queue:last_processed_at'));
    }

    public function test_ops07_queue_connection(): void
    {
        $this->assertEquals('PONG', Redis::ping());
        $this->assertNotNull(config('queue.connections.redis'));
        $this->assertEquals('redis', config('queue.connections.redis.driver'));
    }
}
