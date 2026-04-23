<?php

namespace Tests\Feature;

use App\Events\AiActionConfirmed;
use App\Events\InvoiceCreated;
use App\Events\PaymentRecorded;
use App\Events\SubscriptionActivated;
use App\Events\TrialStarted;
use App\Mail\AiActionConfirmationMail;
use App\Mail\InvoiceCreatedMail;
use App\Mail\OverdueReminderMail;
use App\Mail\PaymentReceivedMail;
use App\Mail\SubscriptionActivatedMail;
use App\Mail\TrialStartedMail;
use App\Services\Email\EmailConfigService;
use App\Services\Email\EmailService;
use App\Services\NotificationDispatcher;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

/**
 * Email System Tests (EM01–EM10).
 *
 * All tests use Mail::fake() — no real emails sent.
 */
class EmailSystemTest extends SmartBizTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Ensure email is globally enabled
        DB::table('platform_settings')->updateOrInsert(
            ['key' => 'email.enabled'],
            ['value' => 'true'],
        );

        // Clean email logs for this workspace
        DB::table('email_logs')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        // Ensure workspace email settings exist
        DB::table('email_settings')->updateOrInsert(
            ['workspace_id' => FoundationSeeder::WORKSPACE_ID],
            ['enabled' => true, 'daily_limit' => 200, 'updated_at' => now()],
        );
    }

    // ═══════════════════════════════════════════════════════════
    // EM01 — Email send success → logged
    // ═══════════════════════════════════════════════════════════

    public function test_em01_email_send_success(): void
    {
        Mail::fake();

        $service = $this->app->make(EmailService::class);
        $logId   = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'test@example.com',
            'Test User',
            new InvoiceCreatedMail('Test User', 'INV-001', 500.00, '2026-05-01'),
            'invoice_created',
            ['event_name' => 'InvoiceCreated', 'related_entity_type' => 'invoice', 'related_entity_id' => Str::uuid()->toString()],
        );

        $this->assertNotNull($logId);

        // Verify email was dispatched
        Mail::assertSent(InvoiceCreatedMail::class);

        // Verify log entry
        $log = DB::table('email_logs')->where('id', $logId)->first();
        $this->assertNotNull($log);
        $this->assertEquals('sent', $log->status);
        $this->assertEquals('invoice_created', $log->template);
        $this->assertEquals('test@example.com', $log->recipient_email);
        $this->assertEquals('InvoiceCreated', $log->event_name);
        $this->assertNotNull($log->sent_at);
    }

    // ═══════════════════════════════════════════════════════════
    // EM02 — Email failure logged
    // ═══════════════════════════════════════════════════════════

    public function test_em02_email_failure_logged(): void
    {
        // Force mail to fail by using a broken transport
        Mail::shouldReceive('to->send')
            ->andThrow(new \RuntimeException('SMTP connection failed'));

        $service = $this->app->make(EmailService::class);
        $logId   = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'fail@example.com',
            'Fail User',
            new InvoiceCreatedMail('Fail User', 'INV-002', 100.00, '2026-06-01'),
            'invoice_created',
            ['event_name' => 'InvoiceCreated'],
        );

        $this->assertNotNull($logId);

        $log = DB::table('email_logs')->where('id', $logId)->first();
        $this->assertEquals('failed', $log->status);
        $this->assertNotNull($log->error_message);
        $this->assertStringContainsString('SMTP', $log->error_message);
    }

    // ═══════════════════════════════════════════════════════════
    // EM03 — All 11 templates render without error
    // ═══════════════════════════════════════════════════════════

    public function test_em03_template_rendering(): void
    {
        $mailables = [
            new \App\Mail\InvoiceCreatedMail('John', 'INV-001', 500, '2026-05-01'),
            new \App\Mail\InvoiceSentMail('John', 'INV-001', 500, '2026-05-01'),
            new \App\Mail\PaymentReceivedMail('John', 500, 'INV-001', 'cash'),
            new \App\Mail\PaymentFailedMail('Workspace', 500),
            new \App\Mail\OverdueReminderMail('John', 'INV-001', 500, 10),
            new \App\Mail\TrialStartedMail('Workspace', '2026-06-01'),
            new \App\Mail\TrialEndingMail('Workspace', 3),
            new \App\Mail\SubscriptionActivatedMail('Workspace', 'Pro Plan'),
            new \App\Mail\SubscriptionExpiredMail('Workspace'),
            new \App\Mail\AccountSuspendedMail('Workspace', 'Payment failure'),
            new \App\Mail\AiActionConfirmationMail('Ahmed', 'contact_create', 'Created new contact'),
        ];

        foreach ($mailables as $mailable) {
            $rendered = $mailable->render();
            $this->assertNotEmpty($rendered);
            $this->assertStringContainsString('SmartBiz AI', $rendered);
        }

        $this->assertCount(11, $mailables);
    }

    // ═══════════════════════════════════════════════════════════
    // EM04 — Event triggers email (InvoiceCreated)
    // ═══════════════════════════════════════════════════════════

    public function test_em04_event_triggers_email(): void
    {
        Mail::fake();

        // Ensure seed contact has email
        $contactId = Str::uuid()->toString();
        DB::table('contacts')->insert([
            'id'           => $contactId,
            'workspace_id' => FoundationSeeder::WORKSPACE_ID,
            'name'         => 'Event Test Customer',
            'email'        => 'event-test@example.com',
            'type'         => 'customer',
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        // Dispatch event
        InvoiceCreated::dispatch(
            FoundationSeeder::WORKSPACE_ID,
            Str::uuid()->toString(),
            'INV-EVENT-001',
            $contactId,
            1500.00,
            '2026-06-15',
        );

        Mail::assertSent(InvoiceCreatedMail::class, function ($mail) {
            return $mail->invoiceNumber === 'INV-EVENT-001';
        });

        DB::table('contacts')->where('id', $contactId)->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // EM05 — NotificationDispatcher sends both channels
    // ═══════════════════════════════════════════════════════════

    public function test_em05_notification_dispatcher_both(): void
    {
        Mail::fake();

        $dispatcher = $this->app->make(NotificationDispatcher::class);
        $results    = $dispatcher->notify(
            FoundationSeeder::WORKSPACE_ID,
            FoundationSeeder::USER_ID,
            ['both'],
            'Test Notification',
            'This is a test message.',
            'both-test@example.com',
            'Both Test User',
            new SubscriptionActivatedMail('TestWorkspace', 'Pro'),
            'subscription_activated',
            'success',
        );

        // In-app notification created
        $this->assertNotNull($results['in_app']);
        $this->assertEquals('Test Notification', $results['in_app']->title);

        // Email sent
        $this->assertNotNull($results['email']);
        Mail::assertSent(SubscriptionActivatedMail::class);
    }

    // ═══════════════════════════════════════════════════════════
    // EM06 — Global toggle disables email
    // ═══════════════════════════════════════════════════════════

    public function test_em06_global_toggle_disables_email(): void
    {
        Mail::fake();

        // Disable globally
        DB::table('platform_settings')->where('key', 'email.enabled')->update(['value' => 'false']);

        $service = $this->app->make(EmailService::class);
        $logId   = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'disabled@example.com',
            'Disabled User',
            new InvoiceCreatedMail('Disabled User', 'INV-003', 100, '2026-07-01'),
            'invoice_created',
        );

        $this->assertNull($logId);
        Mail::assertNothingSent();

        // Re-enable
        DB::table('platform_settings')->where('key', 'email.enabled')->update(['value' => 'true']);
    }

    // ═══════════════════════════════════════════════════════════
    // EM07 — Workspace toggle disables email
    // ═══════════════════════════════════════════════════════════

    public function test_em07_workspace_toggle_disables_email(): void
    {
        Mail::fake();

        DB::table('email_settings')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['enabled' => false]);

        $service = $this->app->make(EmailService::class);
        $logId   = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'ws-disabled@example.com',
            'WS User',
            new InvoiceCreatedMail('WS User', 'INV-004', 200, '2026-08-01'),
            'invoice_created',
        );

        $this->assertNull($logId);
        Mail::assertNothingSent();

        // Re-enable
        DB::table('email_settings')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['enabled' => true]);
    }

    // ═══════════════════════════════════════════════════════════
    // EM08 — Dedup prevents duplicate emails
    // ═══════════════════════════════════════════════════════════

    public function test_em08_dedup_prevents_duplicates(): void
    {
        Mail::fake();

        $entityId = Str::uuid()->toString();
        $service  = $this->app->make(EmailService::class);

        // First send — should work
        $logId1 = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'dedup@example.com',
            'Dedup User',
            new OverdueReminderMail('Dedup User', 'INV-DEDUP', 300, 5),
            'overdue_reminder',
            ['related_entity_type' => 'invoice', 'related_entity_id' => $entityId],
        );

        $this->assertNotNull($logId1);

        // Second send same entity same day — should be deduped
        $logId2 = $service->send(
            FoundationSeeder::WORKSPACE_ID,
            'dedup@example.com',
            'Dedup User',
            new OverdueReminderMail('Dedup User', 'INV-DEDUP', 300, 5),
            'overdue_reminder',
            ['related_entity_type' => 'invoice', 'related_entity_id' => $entityId],
        );

        $this->assertNull($logId2);

        // Only 1 email sent
        Mail::assertSent(OverdueReminderMail::class, 1);
    }

    // ═══════════════════════════════════════════════════════════
    // EM09 — Overdue reminder command runs
    // ═══════════════════════════════════════════════════════════

    public function test_em09_overdue_reminder_command(): void
    {
        Mail::fake();

        // Create an overdue invoice with a contact that has email
        $contactId = Str::uuid()->toString();
        DB::table('contacts')->insert([
            'id'           => $contactId,
            'workspace_id' => FoundationSeeder::WORKSPACE_ID,
            'name'         => 'Overdue Customer',
            'email'        => 'overdue@example.com',
            'type'         => 'customer',
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        $invoiceId = Str::uuid()->toString();
        DB::table('invoices')->insert([
            'id'               => $invoiceId,
            'workspace_id'     => FoundationSeeder::WORKSPACE_ID,
            'contact_id'       => $contactId,
            'invoice_type'     => 'sale',
            'invoice_number'   => 'INV-OVERDUE-001',
            'total_amount'     => 750.00,
            'net_amount'       => 750.00,
            'tax_amount'       => 0,
            'payment_status'   => 'unpaid',
            'due_date'         => now()->subDays(10)->toDateString(),
            'created_at'       => now()->subDays(30),
            'updated_at'       => now(),
        ]);

        $this->artisan('email:send-overdue-reminders')
            ->assertExitCode(0);

        Mail::assertSent(OverdueReminderMail::class, function ($mail) {
            return $mail->invoiceNumber === 'INV-OVERDUE-001';
        });

        // Cleanup
        DB::table('invoices')->where('id', $invoiceId)->delete();
        DB::table('contacts')->where('id', $contactId)->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // EM10 — AI action confirmation triggers email event
    // ═══════════════════════════════════════════════════════════

    public function test_em10_ai_action_confirmation_email(): void
    {
        Mail::fake();

        // Dispatch event
        AiActionConfirmed::dispatch(
            FoundationSeeder::WORKSPACE_ID,
            FoundationSeeder::USER_ID,
            Str::uuid()->toString(),
            'settings',
            'Created new contact: Ahmed',
        );

        Mail::assertSent(AiActionConfirmationMail::class);

        // Verify email log created
        $log = DB::table('email_logs')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->where('template', 'ai_action_confirmed')
            ->first();

        $this->assertNotNull($log);
        $this->assertEquals('AiActionConfirmed', $log->event_name);
    }
}
