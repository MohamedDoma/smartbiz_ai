<?php

namespace App\Console\Commands;

use App\Services\Operations\BackupArchiveManager;
use Illuminate\Console\Command;
use Symfony\Component\Process\Process;
use Throwable;

class RestoreDatabase extends Command
{
    protected $signature = 'db:restore
        {backup : Database backup filename inside BACKUP_PATH}
        {--database= : Restore into this database instead of the configured database}
        {--confirm= : Must equal RESTORE in production}
        {--verify-only : Verify checksum and archive readability without restoring}';

    protected $description = 'Verify or restore a PostgreSQL custom-format backup';

    public function handle(BackupArchiveManager $archives): int
    {
        try {
            $archivePath = $archives->resolve((string) $this->argument('backup'), ['.dump']);
            $metadata = $archives->verify($archivePath);

            $verify = new Process(['pg_restore', '--list', $archivePath]);
            $verify->setTimeout(120);
            $verify->run();

            if (! $verify->isSuccessful()) {
                throw new \RuntimeException('pg_restore could not read this archive.');
            }

            $this->info(sprintf(
                'Backup verified: %s (%.1f MB)',
                basename($archivePath),
                ((int) ($metadata['bytes'] ?? filesize($archivePath))) / 1024 / 1024,
            ));

            if ($this->option('verify-only')) {
                return self::SUCCESS;
            }

            $connectionName = (string) config('operations.restore.database_connection', 'pgsql_owner');
            $connection = config("database.connections.{$connectionName}");

            if (! is_array($connection)) {
                throw new \RuntimeException("Restore database connection [{$connectionName}] is not configured.");
            }
            $configuredDatabase = (string) $connection['database'];
            $targetDatabase = trim((string) ($this->option('database') ?: $configuredDatabase));

            if (! preg_match('/^[A-Za-z0-9_]+$/', $targetDatabase)) {
                $this->error('Database name may contain only letters, numbers, and underscores.');

                return self::FAILURE;
            }

            if (app()->environment('production')) {
                if ($this->option('confirm') !== 'RESTORE') {
                    $this->error('Production restore requires --confirm=RESTORE.');

                    return self::FAILURE;
                }

                if ($targetDatabase === $configuredDatabase && ! app()->isDownForMaintenance()) {
                    $this->error('Put the application into maintenance mode before restoring the configured production database.');

                    return self::FAILURE;
                }
            }

            $process = new Process([
                'pg_restore',
                '--host='.(string) $connection['host'],
                '--port='.(string) $connection['port'],
                '--username='.(string) $connection['username'],
                '--dbname='.$targetDatabase,
                '--clean',
                '--if-exists',
                '--no-owner',
                '--no-privileges',
                '--exit-on-error',
                '--single-transaction',
                $archivePath,
            ]);
            $process->setEnv([
                'PGPASSWORD' => (string) $connection['password'],
                'PGSSLMODE' => (string) ($connection['sslmode'] ?? 'prefer'),
            ]);
            $process->setTimeout((int) config('operations.backup.timeout_seconds', 1800));

            $this->warn("Restoring PostgreSQL database: {$targetDatabase}");
            $process->run(fn (string $type, string $buffer) => $this->output->write($buffer));

            if (! $process->isSuccessful()) {
                throw new \RuntimeException('Database restore failed: '.trim($process->getErrorOutput()));
            }

            $this->info('Database restore completed successfully.');

            return self::SUCCESS;
        } catch (Throwable $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }
    }
}
