@extends('emails.layout')
@section('content')
<h2>Subscription Expired</h2>
<p>Hello,</p>
<p>Your subscription for <strong>{{ $workspaceName }}</strong> has expired.</p>
<p>Reactivate your subscription to continue using SmartBiz AI features.</p>
@if(!empty($reactivationUrl))
<p><a href="{{ $reactivationUrl }}" class="btn">Reactivate</a></p>
@endif
@endsection
