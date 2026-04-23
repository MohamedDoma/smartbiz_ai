<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class AccountSuspendedMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $workspaceName,
        public string $reason,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Account Suspended — SmartBiz AI');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.account_suspended');
    }
}
