<?php

namespace App\Services;

use App\Models\Notification;
use App\Services\Email\EmailService;
use Illuminate\Contracts\Mail\Mailable;
use Illuminate\Support\Facades\Log;

/**
 * Unified notification dispatcher.
 *
 * Sends to in-app, email, or both channels.
 */
class NotificationDispatcher
{
    public function __construct(
        private readonly EmailService $emailService,
    ) {}

    /**
     * Dispatch a notification through one or more channels.
     *
     * @param  string       $workspaceId
     * @param  string|null  $userId         Target user for in-app
     * @param  string[]     $channels       ['in_app', 'email'] or ['both']
     * @param  string       $title          Notification title
     * @param  string       $message        Notification body
     * @param  string|null  $recipientEmail For email channel
     * @param  string|null  $recipientName  For email channel
     * @param  Mailable|null $mailable      For email channel
     * @param  string       $template       Email template key
     * @param  string       $type           Notification type: info|warning|alert|success
     * @param  array        $meta           Extra metadata for email logging
     */
    public function notify(
        string    $workspaceId,
        ?string   $userId,
        array     $channels,
        string    $title,
        string    $message,
        ?string   $recipientEmail = null,
        ?string   $recipientName = null,
        ?Mailable $mailable = null,
        string    $template = '',
        string    $type = 'info',
        array     $meta = [],
    ): array {
        $results = ['in_app' => null, 'email' => null];

        $sendInApp = in_array('in_app', $channels) || in_array('both', $channels);
        $sendEmail = in_array('email', $channels) || in_array('both', $channels);

        // In-app notification
        if ($sendInApp && $userId) {
            $results['in_app'] = Notification::create([
                'workspace_id' => $workspaceId,
                'user_id'      => $userId,
                'title'        => $title,
                'message'      => $message,
                'type'         => $type,
            ]);
        }

        // Email notification
        if ($sendEmail && $recipientEmail && $mailable) {
            $results['email'] = $this->emailService->send(
                $workspaceId,
                $recipientEmail,
                $recipientName ?? '',
                $mailable,
                $template,
                $meta,
            );
        }

        return $results;
    }

    /**
     * Quick in-app-only notification.
     */
    public function inApp(string $workspaceId, string $userId, string $title, string $message, string $type = 'info'): Notification
    {
        return Notification::create([
            'workspace_id' => $workspaceId,
            'user_id'      => $userId,
            'title'        => $title,
            'message'      => $message,
            'type'         => $type,
        ]);
    }
}
