<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class AiActionConfirmationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $userName,
        public string $actionType,
        public string $actionSummary,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'AI Action Confirmed — SmartBiz AI');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.ai_action_confirmed');
    }
}
