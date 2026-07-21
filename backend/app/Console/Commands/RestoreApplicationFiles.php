<?php

namespace App\Console\Commands;

use App\Services\Operations\BackupArchiveManager;
use Illuminate\Console\Command;
use Symfony\Component\Process\Process;
use Throwable;

class RestoreApplicationFiles extends Command
{
    protected $signature = 'files:restore
        {backup : File backup filename inside BACKUP_PATH}
        {--confirm= : Must equal RESTORE in production}
        {--verify-only : Verify checksum and archive contents without restoring}';

    protected $description = 'Verify or restore private and public application files';

    public function handle(BackupArchiveManager $archives): int
    {
        try {
            $archivePath = $archives->resolve((string) $this->argument('backup'), ['.tar.gz']);
            $metadata = $archives->verify($archivePath);

            $list = new Process(['tar', '-tzf', $archivePath]);
            $list->setTimeout(120);
            $list->run();

            if (! $list->isSuccessful()) {
                throw new \RuntimeException('tar could not read this archive.');
            }

            foreach (preg_split('/\R/', trim($list->getOutput())) ?: [] as $entry) {
                $normalized = ltrim($entry, './');
                if ($normalized === '' || str_contains($normalized, '..') || str_starts_with($entry, '/')) {
                    throw new \RuntimeException('Unsafe path detected inside file backup.');
                }

                if (! str_starts_with($normalized, 'private/')
                    && $normalized !== 'private'
                    && ! str_starts_with($normalized, 'public/')
                    && $normalized !== 'public') {
                    throw new \RuntimeException('Unexpected path detected inside file backup.');
                }
            }

            $this->info(sprintf(
                'File backup verified: %s (%.1f MB)',
                basename($archivePath),
                ((int) ($metadata['bytes'] ?? filesize($archivePath))) / 1024 / 1024,
            ));

            if ($this->option('verify-only')) {
                return self::SUCCESS;
            }

            if (app()->environment('production')) {
                if ($this->option('confirm') !== 'RESTORE') {
                    $this->error('Production restore requires --confirm=RESTORE.');

                    return self::FAILURE;
                }

                if (! app()->isDownForMaintenance()) {
                    $this->error('Put the application into maintenance mode before restoring production.');

                    return self::FAILURE;
                }
            }

            $storageRoot = storage_path('app');
            if (! is_dir($storageRoot) && ! mkdir($storageRoot, 0750, true) && ! is_dir($storageRoot)) {
                throw new \RuntimeException('Unable to create application storage directory.');
            }

            $restore = new Process(['tar', '-xzf', $archivePath, '-C', $storageRoot]);
            $restore->setTimeout((int) config('operations.backup.timeout_seconds', 1800));
            $restore->run(fn (string $type, string $buffer) => $this->output->write($buffer));

            if (! $restore->isSuccessful()) {
                throw new \RuntimeException('Application file restore failed: '.trim($restore->getErrorOutput()));
            }

            $this->info('Application files restored successfully.');

            return self::SUCCESS;
        } catch (Throwable $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }
    }
}
