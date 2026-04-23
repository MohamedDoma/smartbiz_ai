@extends('emails.layout')
@section('content')
<h2>Overdue Payment Reminder</h2>
<p>Hello {{ $customerName }},</p>
<p>This is a friendly reminder that the following invoice is overdue.</p>
<div class="highlight">
    <p><strong>Invoice #:</strong> {{ $invoiceNumber }}</p>
    <p><strong>Amount Due:</strong> {{ $currency ?? 'USD' }} {{ number_format($total, 2) }}</p>
    <p><strong>Days Overdue:</strong> {{ $daysOverdue }}</p>
</div>
<p>Please arrange payment at your earliest convenience.</p>
@endsection
