@extends('emails.layout')
@section('content')
<h2>Welcome to SmartBiz AI!</h2>
<p>Hello,</p>
<p>Your free trial for <strong>{{ $workspaceName }}</strong> has started.</p>
<div class="highlight">
    <p><strong>Trial Ends:</strong> {{ $trialEndDate }}</p>
</div>
<p>Explore all features during your trial period. No credit card required.</p>
@endsection
