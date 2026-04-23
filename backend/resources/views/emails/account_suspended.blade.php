@extends('emails.layout')
@section('content')
<h2>Account Suspended</h2>
<p>Hello,</p>
<p>Your account for <strong>{{ $workspaceName }}</strong> has been suspended.</p>
<div class="highlight">
    <p><strong>Reason:</strong> {{ $reason }}</p>
</div>
<p>Please contact support or update your payment method to restore access.</p>
@endsection
