<?php

namespace Tests\Feature;

class AuditLogTest extends SmartBizTestCase
{
    public function test_list_audit_logs(): void
    {
        $response = $this->wsGet('/api/audit-logs');
        $response->assertOk()
            ->assertJsonStructure(['data', 'meta' => ['total']]);
    }

    /** F09 — Show single audit log entry */
    public function test_show_audit_log_entry(): void
    {
        $auditId = 'c3200000-0000-0000-0000-000000000001'; // seeded for WS-A
        $response = $this->wsGet("/api/audit-logs/{$auditId}");
        $response->assertOk()
            ->assertJsonStructure(['data' => ['id', 'action', 'entity_type', 'entity_id', 'new_values']]);
    }
}
