<?php

namespace Tests\Unit;

use App\Exceptions\NoMatchingApprovalWorkflowException;
use PHPUnit\Framework\TestCase;

/**
 * Pure unit tests for the Commission ↔ Approval exception contract.
 *
 * These tests validate the NoMatchingApprovalWorkflowException behavior
 * in isolation — no database, no service container, no mocks.
 *
 * Full controller-level and workflow-lifecycle testing is covered by:
 *  @see \Tests\Feature\CommissionApprovalApiTest
 */
class CommissionApprovalTest extends TestCase
{
    // ─────────────────────────────────────────────────────────
    //  1. Exception carries entity type and workspace context
    // ─────────────────────────────────────────────────────────

    public function test_exception_carries_entity_type_and_workspace_id(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('commission_entry', 'ws-abc-123');

        $this->assertEquals('commission_entry', $exception->entityType);
        $this->assertEquals('ws-abc-123', $exception->workspaceId);
    }

    // ─────────────────────────────────────────────────────────
    //  2. Exception message includes diagnostic context
    // ─────────────────────────────────────────────────────────

    public function test_exception_message_contains_entity_type_and_workspace(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('invoice', 'ws-test-456');

        $this->assertStringContainsString('invoice', $exception->getMessage());
        $this->assertStringContainsString('ws-test-456', $exception->getMessage());
    }

    // ─────────────────────────────────────────────────────────
    //  3. Exception extends RuntimeException (backward compat)
    // ─────────────────────────────────────────────────────────

    public function test_exception_is_a_runtime_exception(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('test', 'ws-1');

        // Extends RuntimeException so that legacy catch blocks still work,
        // but new code should catch the specific type for safety.
        $this->assertInstanceOf(\RuntimeException::class, $exception);
    }

    // ─────────────────────────────────────────────────────────
    //  4. Exception is distinct from generic RuntimeException
    // ─────────────────────────────────────────────────────────

    public function test_exception_is_distinguishable_from_generic_runtime_exception(): void
    {
        $specific = new NoMatchingApprovalWorkflowException('expense', 'ws-1');
        $generic  = new \RuntimeException('Workflow has no active steps.');

        // The controller must be able to catch these separately.
        // NoMatchingApprovalWorkflowException → direct approval is safe.
        // Generic RuntimeException → must propagate (potential data corruption).
        $caughtSpecific = false;
        $caughtGeneric  = false;

        try {
            throw $specific;
        } catch (NoMatchingApprovalWorkflowException) {
            $caughtSpecific = true;
        } catch (\RuntimeException) {
            $caughtGeneric = true;
        }

        $this->assertTrue($caughtSpecific, 'Should catch the specific exception type.');
        $this->assertFalse($caughtGeneric, 'Should NOT fall through to generic RuntimeException.');
    }

    // ─────────────────────────────────────────────────────────
    //  5. Readonly properties are immutable
    // ─────────────────────────────────────────────────────────

    public function test_exception_properties_are_readonly(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('commission_entry', 'ws-1');

        // PHP 8.1+ readonly properties cannot be reassigned.
        // Attempting to set them should throw an Error.
        $this->expectException(\Error::class);
        $exception->entityType = 'something_else';
    }
}
