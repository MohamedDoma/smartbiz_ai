@extends('emails.layout')
@section('content')
<h2>Your Invoice</h2>
<p>Hello {{ $customerName }},</p>
<p>Please find your invoice details below.</p>
<div class="highlight">
    <p><strong>Invoice #:</strong> {{ $invoiceNumber }}</p>
    <p><strong>Amount Due:</strong> {{ $currency ?? 'USD' }} {{ number_format($total, 2) }}</p>
    <p><strong>Due Date:</strong> {{ $dueDate }}</p>
</div>
@if(!empty($link))
<p><a href="{{ $link }}" class="btn">View Invoice</a></p>
@endif
@endsection
