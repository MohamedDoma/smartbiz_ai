<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class PaymentReceivedMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $customerName,
        public float  $amount,
        public string $invoiceNumber,
        public string $method,
        public string $currency = 'USD',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: "Payment Received — Invoice {$this->invoiceNumber}");
    }

    public function content(): Content
    {
        return new Content(view: 'emails.payment_received');
    }
}
