<?php

namespace App\Exceptions;

/**
 * Thrown when a generated or submitted blueprint fails validation.
 * Renders as HTTP 422 with structured error details.
 */
class BlueprintValidationException extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly array $errors = [],
        public readonly array $warnings = [],
    ) {
        parent::__construct($message);
    }

    public function render(): \Illuminate\Http\JsonResponse
    {
        return response()->json([
            'message'  => $this->getMessage(),
            'error'    => 'blueprint_validation_error',
            'errors'   => $this->errors,
            'warnings' => $this->warnings,
        ], 422);
    }
}
