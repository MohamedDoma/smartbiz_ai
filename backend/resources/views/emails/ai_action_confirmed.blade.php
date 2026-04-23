@extends('emails.layout')
@section('content')
<h2>AI Action Confirmed</h2>
<p>Hello {{ $userName }},</p>
<p>An AI-assisted action has been confirmed and executed.</p>
<div class="highlight">
    <p><strong>Action:</strong> {{ $actionType }}</p>
    <p><strong>Summary:</strong> {{ $actionSummary }}</p>
</div>
<p>This action was performed through SmartBiz AI assistant.</p>
@endsection
