<?php
namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class TrialStartedMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public string $workspaceName,
        public string $trialEndDate,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Welcome to SmartBiz AI — Your Trial Has Started');
    }

    public function content(): Content
    {
        return new Content(view: 'emails.trial_started');
    }
}
