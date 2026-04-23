@extends('emails.layout')
@section('content')
<h2>Payment Failed</h2>
<p>Hello,</p>
<p>We were unable to process your payment for <strong>{{ $workspaceName }}</strong>.</p>
<div class="highlight">
    <p><strong>Amount:</strong> {{ $currency ?? 'USD' }} {{ number_format($amount, 2) }}</p>
</div>
<p>Please update your payment method to avoid service interruption.</p>
@if(!empty($retryUrl))
<p><a href="{{ $retryUrl }}" class="btn">Update Payment</a></p>
@endif
@endsection
