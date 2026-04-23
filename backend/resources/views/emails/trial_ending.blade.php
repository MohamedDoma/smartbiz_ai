@extends('emails.layout')
@section('content')
<h2>Your Trial is Ending Soon</h2>
<p>Hello,</p>
<p>Your free trial for <strong>{{ $workspaceName }}</strong> will end in <strong>{{ $daysRemaining }} day(s)</strong>.</p>
<p>Upgrade now to keep your data and continue using all features.</p>
@if(!empty($upgradeUrl))
<p><a href="{{ $upgradeUrl }}" class="btn">Upgrade Now</a></p>
@endif
@endsection
