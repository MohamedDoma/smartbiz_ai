<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class OverdueReminderMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $customerName,
        public string $invoiceNumber,
        public float  $total,
        public int    $daysOverdue,
        public string $currency = 'USD',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: "Overdue Reminder — Invoice {$this->invoiceNumber}");
    }

    public function content(): Content
    {
        return new Content(view: 'emails.overdue_reminder');
    }
}
