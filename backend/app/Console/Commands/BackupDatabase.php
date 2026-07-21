<?php

namespace App\Console\Commands;

use App\Services\Operations\BackupArchiveManager;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Symfony\Component\Process\Process;
use Throwable;

class BackupDatabase extends Command
{
    protected $signature = 'db:backup {--retention= : Days to keep local database backups}';

    protected $description = 'Create an atomic, verified PostgreSQL backup archive';

    public function handle(BackupArchiveManager $archives): int
    {
        $lock = null;
        $temporaryPath = null;

        try {
            $archives->assertFreeSpace();
            $lock = $archives->acquireLock('database-backup');

            $connectionName = (string) config('operations.backup.database_connection', config('database.default'));
            $connection = config("database.connections.{$connectionName}");

            if (! is_array($connection)) {
                throw new \RuntimeException("Backup database connection [{$connectionName}] is not configured.");
            }
            $timestamp = now()->utc()->format('Y-m-d_His');
            $filename = "smartbiz_db_{$timestamp}.dump";
            $temporaryPath = $archives->directory().DIRECTORY_SEPARATOR.'.'.$filename.'.part';

            $this->info("Creating database backup: {$filename}");

            $process = new Process([
                'pg_dump',
                '--host='.(string) $connection['host'],
                '--port='.(string) $connection['port'],
                '--username='.(string) $connection['username'],
                '--dbname='.(string) $connection['database'],
                '--format=custom',
                '--compress=6',
                '--no-owner',
                '--no-privileges',
                '--no-password',
                '--file='.$temporaryPath,
            ]);
            $process->setEnv([
                'PGPASSWORD' => (string) $connection['password'],
                'PGSSLMODE' => (string) ($connection['sslmode'] ?? 'prefer'),
            ]);
            $process->setTimeout((int) config('operations.backup.timeout_seconds', 1800));
            $process->run();

            if (! $process->isSuccessful()) {
                throw new \RuntimeException('pg_dump failed: '.trim($process->getErrorOutput()));
            }

            if (config('operations.backup.verify_archive', true)) {
                $verify = new Process(['pg_restore', '--list', $temporaryPath]);
                $verify->setTimeout(120);
                $verify->run();

                if (! $verify->isSuccessful()) {
                    throw new \RuntimeException('pg_restore could not read the generated archive.');
                }
            }

            $metadata = $archives->finalize($temporaryPath, $filename, [
                'type' => 'database',
                'format' => 'postgresql-custom',
                'database' => (string) $connection['database'],
            ]);
            $temporaryPath = null;

            $retention = $this->option('retention');
            $retentionDays = $retention !== null
                ? max(1, (int) $retention)
                : (int) config('operations.backup.retention_days', 30);
            $removed = $archives->clean('smartbiz_db_', $retentionDays);

            $this->info(sprintf(
                'Database backup complete: %s (%.1f MB, sha256 verified)',
                $filename,
                ((int) $metadata['bytes']) / 1024 / 1024,
            ));

            if ($removed > 0) {
                $this->info("Removed {$removed} expired database backup(s).");
            }

            return self::SUCCESS;
        } catch (Throwable $exception) {
            if ($temporaryPath !== null) {
                @unlink($temporaryPath);
            }

            Log::error('Database backup failed.', ['exception' => $exception]);
            $this->error($exception->getMessage());

            return self::FAILURE;
        } finally {
            $archives->releaseLock($lock);
        }
    }
}
