<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

class BackupDatabase extends Command
{
    protected $signature = 'db:backup {--retention=30 : Days to keep backups}';
    protected $description = 'Backup PostgreSQL database using pg_dump';

    public function handle(): int
    {
        $dbHost     = config('database.connections.pgsql.host');
        $dbPort     = config('database.connections.pgsql.port');
        $dbName     = config('database.connections.pgsql.database');
        $dbUser     = config('database.connections.pgsql.username');
        $dbPassword = config('database.connections.pgsql.password');

        $backupDir = storage_path('backups');
        if (! is_dir($backupDir)) {
            mkdir($backupDir, 0750, true);
        }

        $timestamp = now()->format('Y-m-d_His');
        $filename  = "smartbiz_{$timestamp}.sql.gz";
        $filepath  = "{$backupDir}/{$filename}";

        $this->info("Backing up database '{$dbName}' to {$filename}...");

        $cmd = sprintf(
            'PGPASSWORD=%s pg_dump -h %s -p %s -U %s %s | gzip > %s',
            escapeshellarg($dbPassword),
            escapeshellarg($dbHost),
            escapeshellarg($dbPort),
            escapeshellarg($dbUser),
            escapeshellarg($dbName),
            escapeshellarg($filepath),
        );

        $result = null;
        $output = null;
        exec($cmd, $output, $result);

        if ($result !== 0) {
            $this->error("Backup failed with exit code {$result}");
            return self::FAILURE;
        }

        $size = filesize($filepath);
        $this->info("Backup complete: {$filename} (" . number_format($size / 1024, 1) . " KB)");

        // Cleanup old backups
        $retention = (int) $this->option('retention');
        $this->cleanOldBackups($backupDir, $retention);

        return self::SUCCESS;
    }

    private function cleanOldBackups(string $dir, int $retentionDays): void
    {
        $cutoff = now()->subDays($retentionDays)->timestamp;
        $files  = glob("{$dir}/smartbiz_*.sql.gz");

        $removed = 0;
        foreach ($files as $file) {
            if (filemtime($file) < $cutoff) {
                unlink($file);
                $removed++;
            }
        }

        if ($removed > 0) {
            $this->info("Removed {$removed} backup(s) older than {$retentionDays} days.");
        }
    }
}
