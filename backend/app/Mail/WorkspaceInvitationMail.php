<?php

namespace App\Mail;

use App\Models\WorkspaceInvitation;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class WorkspaceInvitationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public WorkspaceInvitation $invitation,
        public string $inviteUrl,
    ) {
    }

    public function envelope(): Envelope
    {
        $workspaceName = $this->invitation->workspace?->name ?? 'SmartBiz AI';
        $isArabic = $this->invitation->preferred_locale === 'ar';

        return new Envelope(
            subject: $isArabic
                ? "دعوة للانضمام إلى {$workspaceName} على SmartBiz AI"
                : "You're invited to join {$workspaceName} on SmartBiz AI",
        );
    }

    public function content(): Content
    {
        return new Content(view: 'emails.workspace_invitation');
    }
}
