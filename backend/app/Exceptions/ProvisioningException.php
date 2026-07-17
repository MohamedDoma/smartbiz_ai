<?php

namespace App\Exceptions;

/**
 * Domain exception for provisioning failures.
 * Carries a machine-readable error code and optional structured context
 * for API responses and diagnostics.
 */
class ProvisioningException extends \RuntimeException
{
    private string $errorCode;

    /** @var array<string,mixed> Additional context (entity_type, local_key, etc.) */
    private array $context;

    public function __construct(
        string $message,
        string $errorCode,
        int $httpCode = 422,
        ?\Throwable $previous = null,
        array $context = [],
    ) {
        parent::__construct($message, $httpCode, $previous);
        $this->errorCode = $errorCode;
        $this->context   = $context;
    }

    public function getErrorCode(): string
    {
        return $this->errorCode;
    }

    /** @return array<string,mixed> */
    public function getContext(): array
    {
        return $this->context;
    }
}

