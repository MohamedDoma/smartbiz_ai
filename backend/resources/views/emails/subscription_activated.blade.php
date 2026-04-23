@extends('emails.layout')
@section('content')
<h2>Subscription Activated</h2>
<p>Hello,</p>
<p>Your subscription for <strong>{{ $workspaceName }}</strong> is now active!</p>
<div class="highlight">
    <p><strong>Plan:</strong> {{ $planName }}</p>
</div>
<p>Thank you for choosing SmartBiz AI.</p>
@endsection
