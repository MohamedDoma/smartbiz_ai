<?php

namespace Tests\Feature;

class NotificationsTest extends SmartBizTestCase
{
    public function test_list_notifications(): void
    {
        $response = $this->wsGet('/api/notifications');
        $response->assertOk()
            ->assertJsonStructure(['data', 'meta' => ['unread_count']]);
    }

    public function test_list_shows_unread_count(): void
    {
        $response = $this->wsGet('/api/notifications');
        $this->assertArrayHasKey('unread_count', $response->json('meta'));
    }

    /** F07 — Mark single notification as read */
    public function test_mark_single_notification_read(): void
    {
        // Create a notification for this workspace/user
        $notif = \App\Models\Notification::create([
            'workspace_id' => \Database\Seeders\FoundationSeeder::WORKSPACE_ID,
            'user_id'      => \Database\Seeders\FoundationSeeder::USER_ID,
            'title'        => 'Test notification',
            'message'      => 'This is a test notification',
            'type'         => 'info',
            'is_read'      => false,
        ]);

        $response = $this->wsPost("/api/notifications/{$notif->id}/read");
        $response->assertOk()
            ->assertJsonPath('data.is_read', true);
    }

    /** F08 — Mark all notifications as read */
    public function test_mark_all_notifications_read(): void
    {
        $response = $this->wsPost('/api/notifications/read-all');
        $response->assertOk()
            ->assertJsonStructure(['message']);
    }
}
