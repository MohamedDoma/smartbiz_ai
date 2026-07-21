<?php

namespace App\Console\Commands;

use App\Services\Operations\BackupArchiveManager;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Symfony\Component\Process\Process;
use Throwable;

class BackupApplicationFiles extends Command
{
    protected $signature = 'files:backup {--retention= : Days to keep local file backups}';

    protected $description = 'Create an atomic, verified archive of private and public application files';

    public function handle(BackupArchiveManager $archives): int
    {
        $lock = null;
        $temporaryPath = null;

        try {
            $archives->assertFreeSpace();
            $lock = $archives->acquireLock('files-backup');

            $storageRoot = storage_path('app');
            foreach (['private', 'public'] as $directory) {
                $path = $storageRoot.DIRECTORY_SEPARATOR.$directory;
                if (! is_dir($path) && ! mkdir($path, 0750, true) && ! is_dir($path)) {
                    throw new \RuntimeException("Unable to create storage directory: {$path}");
                }
            }

            $timestamp = now()->utc()->format('Y-m-d_His');
            $filename = "smartbiz_files_{$timestamp}.tar.gz";
            $temporaryPath = $archives->directory().DIRECTORY_SEPARATOR.'.'.$filename.'.part';

            $this->info("Creating application files backup: {$filename}");

            $process = new Process([
                'tar',
                '-czf',
                $temporaryPath,
                '-C',
                $storageRoot,
                'private',
                'public',
            ]);
            $process->setTimeout((int) config('operations.backup.timeout_seconds', 1800));
            $process->run();

            if (! $process->isSuccessful()) {
                throw new \RuntimeException('File archive creation failed: '.trim($process->getErrorOutput()));
            }

            $verify = new Process(['tar', '-tzf', $temporaryPath]);
            $verify->setTimeout(120);
            $verify->run();

            if (! $verify->isSuccessful()) {
                throw new \RuntimeException('tar could not read the generated file archive.');
            }

            $metadata = $archives->finalize($temporaryPath, $filename, [
                'type' => 'files',
                'format' => 'tar-gzip',
                'paths' => ['storage/app/private', 'storage/app/public'],
            ]);
            $temporaryPath = null;

            $retention = $this->option('retention');
            $retentionDays = $retention !== null
                ? max(1, (int) $retention)
                : (int) config('operations.backup.retention_days', 30);
            $removed = $archives->clean('smartbiz_files_', $retentionDays);

            $this->info(sprintf(
                'Application files backup complete: %s (%.1f MB, sha256 verified)',
                $filename,
                ((int) $metadata['bytes']) / 1024 / 1024,
            ));

            if ($removed > 0) {
                $this->info("Removed {$removed} expired file backup(s).");
            }

            return self::SUCCESS;
        } catch (Throwable $exception) {
            if ($temporaryPath !== null) {
                @unlink($temporaryPath);
            }

            Log::error('Application files backup failed.', ['exception' => $exception]);
            $this->error($exception->getMessage());

            return self::FAILURE;
        } finally {
            $archives->releaseLock($lock);
        }
    }
}
