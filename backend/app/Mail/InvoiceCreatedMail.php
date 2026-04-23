<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class InvoiceCreatedMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $customerName,
        public string $invoiceNumber,
        public float  $total,
        public string $dueDate,
        public string $currency = 'USD',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: "Invoice {$this->invoiceNumber} Created");
    }

    public function content(): Content
    {
        return new Content(view: 'emails.invoice_created');
    }
}
