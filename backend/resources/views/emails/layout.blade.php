<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #333; line-height: 1.6; margin: 0; padding: 0; background: #f4f4f7; }
        .container { max-width: 600px; margin: 0 auto; background: #fff; }
        .header { background: #1a1a2e; padding: 24px 32px; text-align: center; }
        .header h1 { color: #fff; margin: 0; font-size: 22px; font-weight: 600; }
        .body { padding: 32px; }
        .footer { background: #f4f4f7; padding: 20px 32px; text-align: center; font-size: 12px; color: #888; }
        .btn { display: inline-block; padding: 12px 28px; background: #4f46e5; color: #fff; text-decoration: none; border-radius: 6px; font-weight: 600; }
        .highlight { background: #f0f0ff; padding: 16px; border-radius: 8px; margin: 16px 0; }
        .highlight p { margin: 4px 0; }
    </style>
</head>
<body>
<div class="container">
    <div class="header"><h1>SmartBiz AI</h1></div>
    <div class="body">
        @yield('content')
    </div>
    <div class="footer">
        <p>&copy; {{ date('Y') }} SmartBiz AI. All rights reserved.</p>
        <p>This is an automated message. Please do not reply directly.</p>
    </div>
</div>
</body>
</html>
