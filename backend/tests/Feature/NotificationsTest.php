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
        $notifId = 'c3100000-0000-0000-0000-000000000001'; // seeded for admin user
        $response = $this->wsPost("/api/notifications/{$notifId}/read");
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
