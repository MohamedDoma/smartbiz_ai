<?php

namespace App\Services\Operations;

use Illuminate\Support\Facades\Storage;
use RuntimeException;
use Throwable;

class BackupArchiveManager
{
    public function directory(): string
    {
        $directory = rtrim((string) config('operations.backup.path'), DIRECTORY_SEPARATOR);

        if ($directory === '') {
            throw new RuntimeException('BACKUP_PATH is not configured.');
        }

        if (! is_dir($directory) && ! mkdir($directory, 0750, true) && ! is_dir($directory)) {
            throw new RuntimeException("Unable to create backup directory: {$directory}");
        }

        return $directory;
    }

    public function assertFreeSpace(): void
    {
        $minimumBytes = max(0, (int) config('operations.backup.minimum_free_mb', 1024)) * 1024 * 1024;
        $freeBytes = @disk_free_space($this->directory());

        if ($freeBytes !== false && $freeBytes < $minimumBytes) {
            throw new RuntimeException(sprintf(
                'Backup aborted: only %.1f MB are free; at least %.1f MB are required.',
                $freeBytes / 1024 / 1024,
                $minimumBytes / 1024 / 1024,
            ));
        }
    }

    /**
     * @return resource
     */
    public function acquireLock(string $name)
    {
        $path = $this->directory().DIRECTORY_SEPARATOR.'.'.$name.'.lock';
        $handle = fopen($path, 'c');

        if ($handle === false || ! flock($handle, LOCK_EX | LOCK_NB)) {
            if (is_resource($handle)) {
                fclose($handle);
            }

            throw new RuntimeException("Another {$name} operation is already running.");
        }

        return $handle;
    }

    /**
     * @param  resource|null  $handle
     */
    public function releaseLock($handle): void
    {
        if (! is_resource($handle)) {
            return;
        }

        flock($handle, LOCK_UN);
        fclose($handle);
    }

    /**
     * @param  array<string, mixed>  $metadata
     * @return array<string, mixed>
     */
    public function finalize(string $temporaryPath, string $filename, array $metadata): array
    {
        if (! is_file($temporaryPath) || filesize($temporaryPath) === 0) {
            throw new RuntimeException('Backup archive is empty or missing.');
        }

        $finalPath = $this->directory().DIRECTORY_SEPARATOR.$filename;

        if (file_exists($finalPath)) {
            throw new RuntimeException("Backup already exists: {$filename}");
        }

        if (! rename($temporaryPath, $finalPath)) {
            throw new RuntimeException("Unable to finalize backup archive: {$filename}");
        }

        @chmod($finalPath, 0640);

        $checksum = hash_file('sha256', $finalPath);
        if ($checksum === false) {
            @unlink($finalPath);
            throw new RuntimeException('Unable to calculate backup checksum.');
        }

        $metadata = array_merge($metadata, [
            'filename' => $filename,
            'created_at' => now()->utc()->toIso8601String(),
            'bytes' => filesize($finalPath),
            'sha256' => $checksum,
            'verified' => true,
            'app_version' => config('app.version', '1.0.0'),
        ]);

        try {
            $this->atomicWrite($finalPath.'.sha256', "{$checksum}  {$filename}\n");
            $this->atomicWrite(
                $finalPath.'.json',
                json_encode($metadata, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)."\n",
            );
        } catch (Throwable $exception) {
            @unlink($finalPath);
            @unlink($finalPath.'.sha256');
            @unlink($finalPath.'.json');

            throw $exception;
        }

        $this->mirror($finalPath, $metadata);

        return $metadata;
    }

    /**
     * @return array<string, mixed>
     */
    public function verify(string $archivePath): array
    {
        if (! is_file($archivePath)) {
            throw new RuntimeException("Backup archive not found: {$archivePath}");
        }

        $checksumPath = $archivePath.'.sha256';
        if (! is_file($checksumPath)) {
            throw new RuntimeException("Checksum file not found: {$checksumPath}");
        }

        $expected = strtok(trim((string) file_get_contents($checksumPath)), " \t");
        $actual = hash_file('sha256', $archivePath);

        if (! is_string($expected) || strlen($expected) !== 64 || $actual === false || ! hash_equals($expected, $actual)) {
            throw new RuntimeException('Backup checksum verification failed.');
        }

        $metadataPath = $archivePath.'.json';
        $metadata = [];

        if (is_file($metadataPath)) {
            $decoded = json_decode((string) file_get_contents($metadataPath), true, flags: JSON_THROW_ON_ERROR);
            $metadata = is_array($decoded) ? $decoded : [];
        }

        return array_merge($metadata, [
            'filename' => basename($archivePath),
            'bytes' => filesize($archivePath),
            'sha256' => $actual,
        ]);
    }

    /**
     * @param  list<string>  $extensions
     */
    public function resolve(string $input, array $extensions): string
    {
        $directory = realpath($this->directory());
        if ($directory === false) {
            throw new RuntimeException('Backup directory cannot be resolved.');
        }

        $candidate = str_starts_with($input, DIRECTORY_SEPARATOR)
            ? $input
            : $directory.DIRECTORY_SEPARATOR.basename($input);

        $resolved = realpath($candidate);
        if ($resolved === false || ! is_file($resolved)) {
            throw new RuntimeException("Backup archive not found: {$input}");
        }

        if ($resolved !== $directory && ! str_starts_with($resolved, $directory.DIRECTORY_SEPARATOR)) {
            throw new RuntimeException('Backup archive must be inside BACKUP_PATH.');
        }

        $matchesExtension = collect($extensions)->contains(
            fn (string $extension): bool => str_ends_with($resolved, $extension),
        );

        if (! $matchesExtension) {
            throw new RuntimeException('Unsupported backup archive type.');
        }

        return $resolved;
    }

    public function clean(string $prefix, int $retentionDays): int
    {
        $cutoff = now()->subDays(max(1, $retentionDays))->timestamp;
        $removed = 0;

        foreach (glob($this->directory().DIRECTORY_SEPARATOR.$prefix.'*') ?: [] as $path) {
            if (! is_file($path) || str_ends_with($path, '.json') || str_ends_with($path, '.sha256')) {
                continue;
            }

            $modifiedAt = filemtime($path);
            if ($modifiedAt !== false && $modifiedAt < $cutoff) {
                @unlink($path);
                @unlink($path.'.sha256');
                @unlink($path.'.json');
                $removed++;
            }
        }

        return $removed;
    }

    /**
     * @return array<string, mixed>|null
     */
    public function latest(string $type): ?array
    {
        $latest = null;

        foreach (glob($this->directory().DIRECTORY_SEPARATOR.'*.json') ?: [] as $metadataPath) {
            try {
                $metadata = json_decode((string) file_get_contents($metadataPath), true, flags: JSON_THROW_ON_ERROR);
            } catch (Throwable) {
                continue;
            }

            if (! is_array($metadata) || ($metadata['type'] ?? null) !== $type) {
                continue;
            }

            $createdAt = strtotime((string) ($metadata['created_at'] ?? ''));
            if ($createdAt === false) {
                continue;
            }

            if ($latest === null || $createdAt > $latest['_timestamp']) {
                $metadata['_timestamp'] = $createdAt;
                $metadata['_path'] = substr($metadataPath, 0, -5);
                $latest = $metadata;
            }
        }

        return $latest;
    }

    private function atomicWrite(string $path, string $contents): void
    {
        $temporaryPath = $path.'.part';

        if (file_put_contents($temporaryPath, $contents, LOCK_EX) === false || ! rename($temporaryPath, $path)) {
            @unlink($temporaryPath);
            throw new RuntimeException("Unable to write backup sidecar: {$path}");
        }

        @chmod($path, 0640);
    }

    /**
     * @param  array<string, mixed>  $metadata
     */
    private function mirror(string $archivePath, array $metadata): void
    {
        $diskName = trim((string) config('operations.backup.mirror_disk'));
        if ($diskName === '') {
            return;
        }

        $prefix = trim((string) config('operations.backup.mirror_prefix', 'smartbiz'), '/');
        $createdAt = strtotime((string) ($metadata['created_at'] ?? 'now')) ?: time();
        $remoteDirectory = implode('/', array_filter([
            $prefix,
            gmdate('Y', $createdAt),
            gmdate('m', $createdAt),
        ]));

        try {
            $disk = Storage::disk($diskName);
            $stream = fopen($archivePath, 'rb');

            if ($stream === false) {
                throw new RuntimeException('Unable to open backup archive for mirroring.');
            }

            try {
                if (! $disk->writeStream($remoteDirectory.'/'.basename($archivePath), $stream)) {
                    throw new RuntimeException('Mirror disk rejected the backup archive.');
                }
            } finally {
                fclose($stream);
            }

            $disk->put($remoteDirectory.'/'.basename($archivePath).'.sha256', (string) file_get_contents($archivePath.'.sha256'));
            $disk->put($remoteDirectory.'/'.basename($archivePath).'.json', (string) file_get_contents($archivePath.'.json'));
        } catch (Throwable $exception) {
            if (config('operations.backup.mirror_required', false)) {
                throw new RuntimeException('Backup mirror failed: '.$exception->getMessage(), previous: $exception);
            }

            report($exception);
        }
    }
}
