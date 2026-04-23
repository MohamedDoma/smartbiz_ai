<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class SubscriptionExpiredMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $workspaceName,
        public string $reactivationUrl = '',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Subscription Expired — SmartBiz AI');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.subscription_expired');
    }
}
