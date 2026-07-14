<?php

return [
    /*
    |--------------------------------------------------------------------------
    | AI Feature Toggle
    |--------------------------------------------------------------------------
    */
    'enabled' => env('AI_ENABLED', false),

    /*
    |--------------------------------------------------------------------------
    | OpenAI Configuration
    |--------------------------------------------------------------------------
    */
    'openai' => [
        'api_key'       => env('OPENAI_API_KEY', ''),
        'default_model' => env('OPENAI_DEFAULT_MODEL', 'gpt-4o-mini'),
        'smart_model'   => env('OPENAI_SMART_MODEL', 'gpt-4o'),
        'timeout'       => (int) env('OPENAI_TIMEOUT', 30),
        'max_retries'   => (int) env('OPENAI_MAX_RETRIES', 2),
    ],

    /*
    |--------------------------------------------------------------------------
    | Budget & Limits
    |--------------------------------------------------------------------------
    */
    'budget' => [
        'monthly_usd'         => (float) env('AI_MONTHLY_BUDGET_USD', 30),
        'daily_message_limit'  => (int) env('AI_DAILY_MESSAGE_LIMIT', 200),
        'monthly_message_limit' => (int) env('AI_MONTHLY_MESSAGE_LIMIT', 3000),
    ],

    /*
    |--------------------------------------------------------------------------
    | Cost Estimates (USD per 1M tokens) — approximate, for monitoring only.
    |--------------------------------------------------------------------------
    */
    'cost_rates' => [
        'gpt-4o-mini' => ['input' => 0.15, 'output' => 0.60],
        'gpt-4o'      => ['input' => 2.50, 'output' => 10.00],
        'gpt-4-turbo' => ['input' => 10.00, 'output' => 30.00],
        'gpt-3.5-turbo' => ['input' => 0.50, 'output' => 1.50],
        '_default'    => ['input' => 1.00, 'output' => 3.00],
    ],
];
