@extends('emails.layout')

@section('content')
@php
    $isArabic = $invitation->preferred_locale === 'ar';
    $workspaceName = $invitation->workspace?->name ?? 'SmartBiz AI';
    $inviteeName = $invitation->full_name ?: $invitation->email;
    $roleNames = $invitation->invitationRoles->map(fn ($item) => $item->role?->name)->filter()->join(', ');
    if ($roleNames === '' && $invitation->role) $roleNames = $invitation->role->name;
@endphp

<div dir="{{ $isArabic ? 'rtl' : 'ltr' }}" style="text-align: {{ $isArabic ? 'right' : 'left' }}">
    <h2 style="margin-top: 0; color: #172554; font-size: 24px;">
        {{ $isArabic ? 'مرحباً ' . $inviteeName : 'Hello ' . $inviteeName }}
    </h2>

    <p style="font-size: 16px; color: #475569;">
        @if($isArabic)
            دعاك <strong>{{ $invitation->invitedByUser?->full_name ?? 'مسؤول الشركة' }}</strong>
            للانضمام إلى <strong>{{ $workspaceName }}</strong> على SmartBiz AI.
        @else
            <strong>{{ $invitation->invitedByUser?->full_name ?? 'A workspace administrator' }}</strong>
            invited you to join <strong>{{ $workspaceName }}</strong> on SmartBiz AI.
        @endif
    </p>

    <div class="highlight" style="border: 1px solid #dbeafe; background: #eff6ff;">
        @if($roleNames !== '')
            <p><strong>{{ $isArabic ? 'الدور:' : 'Role:' }}</strong> {{ $roleNames }}</p>
        @endif
        @if($invitation->job_title)
            <p><strong>{{ $isArabic ? 'المسمى الوظيفي:' : 'Job title:' }}</strong> {{ $invitation->job_title }}</p>
        @endif
        @if($invitation->department)
            <p><strong>{{ $isArabic ? 'القسم:' : 'Department:' }}</strong> {{ $invitation->department->name }}</p>
        @endif
        @if($invitation->team)
            <p><strong>{{ $isArabic ? 'الفريق:' : 'Team:' }}</strong> {{ $invitation->team->name }}</p>
        @endif
        <p><strong>{{ $isArabic ? 'تنتهي الدعوة:' : 'Invitation expires:' }}</strong> {{ $invitation->expires_at?->format('Y-m-d H:i T') }}</p>
    </div>

    <p style="text-align: center; margin: 28px 0;">
        <a href="{{ $inviteUrl }}" class="btn" style="background: #2563eb; color: #ffffff; border-radius: 10px;">
            {{ $isArabic ? 'قبول الدعوة' : 'Accept invitation' }}
        </a>
    </p>

    <p style="font-size: 13px; color: #64748b;">
        {{ $isArabic ? 'إذا لم يعمل الزر، انسخ الرابط التالي وافتحه في المتصفح:' : 'If the button does not work, copy and open this link:' }}
    </p>
    <p style="font-size: 12px; word-break: break-all; color: #2563eb;">{{ $inviteUrl }}</p>

    <p style="font-size: 13px; color: #94a3b8; margin-top: 24px;">
        {{ $isArabic ? 'إذا لم تكن تتوقع هذه الدعوة، يمكنك تجاهل الرسالة بأمان.' : 'If you were not expecting this invitation, you can safely ignore this email.' }}
    </p>
</div>
@endsection
