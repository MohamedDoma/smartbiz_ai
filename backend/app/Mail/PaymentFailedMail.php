<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class PaymentFailedMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $workspaceName,
        public float  $amount,
        public string $currency = 'USD',
        public string $retryUrl = '',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Payment Failed — Action Required');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.payment_failed');
    }
}
