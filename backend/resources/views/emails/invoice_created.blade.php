@extends('emails.layout')
@section('content')
<h2>Invoice Created</h2>
<p>Hello {{ $customerName }},</p>
<p>A new invoice has been created for you.</p>
<div class="highlight">
    <p><strong>Invoice #:</strong> {{ $invoiceNumber }}</p>
    <p><strong>Amount:</strong> {{ $currency ?? 'USD' }} {{ number_format($total, 2) }}</p>
    <p><strong>Due Date:</strong> {{ $dueDate }}</p>
</div>
<p>If you have any questions, please contact us.</p>
@endsection
