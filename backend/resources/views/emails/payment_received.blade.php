@extends('emails.layout')
@section('content')
<h2>Payment Received</h2>
<p>Hello {{ $customerName }},</p>
<p>We have received your payment. Thank you!</p>
<div class="highlight">
    <p><strong>Invoice #:</strong> {{ $invoiceNumber }}</p>
    <p><strong>Amount Paid:</strong> {{ $currency ?? 'USD' }} {{ number_format($amount, 2) }}</p>
    <p><strong>Method:</strong> {{ ucfirst($method) }}</p>
</div>
@endsection
