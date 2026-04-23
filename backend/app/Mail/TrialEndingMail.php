<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class TrialEndingMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $workspaceName,
        public int    $daysRemaining,
        public string $upgradeUrl = '',
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: "Your Trial Ends in {$this->daysRemaining} Day(s)");
    }

    public function content(): Content
    {
        return new Content(view: 'emails.trial_ending');
    }
}
