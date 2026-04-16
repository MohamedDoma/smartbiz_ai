<?php

namespace Tests\Feature;

class WorkspaceIsolationTest extends SmartBizTestCase
{
    public function test_ping_with_valid_workspace(): void
    {
        $response = $this->wsGet('/api/ping');

        $response->assertOk()
            ->assertJsonStructure(['status', 'workspace_id', 'membership_id', 'user_id'])
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('workspace_id', $this->workspaceId);
    }

    public function test_request_without_workspace_header(): void
    {
        $response = $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->getJson('/api/ping');

        $response->assertStatus(400)
            ->assertJsonPath('error', 'workspace_required');
    }

    public function test_request_with_invalid_workspace(): void
    {
        $response = $this->wsGet('/api/ping', [
            'X-Workspace-Id' => '99999999-9999-9999-9999-999999999999',
        ]);

        $response->assertStatus(403)
            ->assertJsonPath('error', 'workspace_access_denied');
    }
}
