<?php

namespace App\Services\Invitations;

use App\Mail\WorkspaceInvitationMail;
use App\Models\WorkspaceInvitation;
use App\Services\Email\EmailService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class WorkspaceInvitationDeliveryService
{
    public function __construct(
        private readonly EmailService $emails,
    ) {
    }

    public function issueToken(WorkspaceInvitation $invitation): string
    {
        $rawToken = Str::random(64);

        $invitation->forceFill([
            'token_hash'      => hash('sha256', $rawToken),
            'token_encrypted' => $rawToken,
        ])->save();

        return $rawToken;
    }

    public function inviteUrl(string $rawToken): string
    {
        $base = rtrim((string) config('app.frontend_url', config('app.url')), '/');

        return $base . '/#/invite/' . rawurlencode($rawToken);
    }

    public function storedInviteUrl(WorkspaceInvitation $invitation): ?string
    {
        $rawToken = $invitation->token_encrypted;

        return is_string($rawToken) && $rawToken !== ''
            ? $this->inviteUrl($rawToken)
            : null;
    }

    public function send(WorkspaceInvitation $invitation, string $rawToken): bool
    {
        $invitation->loadMissing([
            'workspace',
            'department:id,name',
            'team:id,name',
            'invitedByUser:id,full_name,email',
            'role',
            'invitationRoles.role',
        ]);

        try {
            $logId = $this->emails->send(
                workspaceId: $invitation->workspace_id,
                recipientEmail: $invitation->email,
                recipientName: $invitation->full_name ?: $invitation->email,
                mailable: new WorkspaceInvitationMail(
                    invitation: $invitation,
                    inviteUrl: $this->inviteUrl($rawToken),
                ),
                template: 'workspace_invitation',
                meta: [
                    'template_version' => 'v1',
                    'actor_user_id' => $invitation->invited_by_user_id,
                    'event_name' => 'workspace_invitation.sent',
                    'correlation_key' => $invitation->id . ':' . ((int) $invitation->send_count + 1),
                    'extra' => [
                        'invitation_id' => $invitation->id,
                        'workspace_id' => $invitation->workspace_id,
                    ],
                ],
            );

            $log = $logId
                ? DB::table('email_logs')->where('id', $logId)->first(['status', 'error_message'])
                : null;
            $sent = $log?->status === 'sent';

            $invitation->forceFill([
                'last_sent_at'    => now(),
                'send_count'      => ((int) $invitation->send_count) + 1,
                'delivery_status' => $sent ? 'sent' : 'failed',
                'delivery_error'  => $sent
                    ? null
                    : Str::limit(
                        $log?->error_message
                            ?? 'Email delivery is disabled or the workspace daily limit was reached.',
                        1000,
                    ),
            ])->save();

            return $sent;
        } catch (\Throwable $e) {
            report($e);

            $invitation->forceFill([
                'last_sent_at'    => now(),
                'send_count'      => ((int) $invitation->send_count) + 1,
                'delivery_status' => 'failed',
                'delivery_error'  => Str::limit($e->getMessage(), 1000),
            ])->save();

            return false;
        }
    }
}
