<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; color: #0f172a; line-height: 1.6; margin: 0; padding: 0; background: #f1f5f9; }
        .outer { width: 100%; padding: 28px 12px; box-sizing: border-box; }
        .container { max-width: 620px; margin: 0 auto; background: #fff; border-radius: 18px; overflow: hidden; box-shadow: 0 10px 30px rgba(15, 23, 42, .08); }
        .header { background: linear-gradient(135deg, #eff6ff, #ffffff); padding: 24px 32px; text-align: center; border-bottom: 1px solid #dbeafe; }
        .logo { max-width: 220px; height: 52px; display: inline-block; }
        .body { padding: 34px 32px; }
        .footer { background: #f8fafc; padding: 22px 32px; text-align: center; font-size: 12px; color: #64748b; border-top: 1px solid #e2e8f0; }
        .footer p { margin: 4px 0; }
        .btn { display: inline-block; padding: 13px 30px; background: #2563eb; color: #fff !important; text-decoration: none; border-radius: 10px; font-weight: 700; }
        .highlight { background: #eff6ff; padding: 18px; border-radius: 12px; margin: 20px 0; }
        .highlight p { margin: 5px 0; }
        @media (max-width: 640px) { .outer { padding: 0; } .container { border-radius: 0; } .header, .body, .footer { padding-left: 20px; padding-right: 20px; } }
    </style>
</head>
<body>
<div class="outer">
    <div class="container">
        <div class="header">
            <img class="logo" src="{{ config('mail.logo_url') }}" alt="SmartBiz AI">
        </div>
        <div class="body">@yield('content')</div>
        <div class="footer">
            <p>&copy; {{ date('Y') }} SmartBiz AI. All rights reserved.</p>
            <p>This is an automated message. Please do not reply directly.</p>
        </div>
    </div>
</div>
</body>
</html>
