<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Stripe API Keys
    |--------------------------------------------------------------------------
    */
    'secret_key'       => env('STRIPE_SECRET_KEY', ''),
    'publishable_key'  => env('STRIPE_PUBLISHABLE_KEY', ''),
    'webhook_secret'   => env('STRIPE_WEBHOOK_SECRET', ''),

    /*
    |--------------------------------------------------------------------------
    | Default Currency
    |--------------------------------------------------------------------------
    */
    'currency' => env('STRIPE_CURRENCY', 'usd'),

    /*
    |--------------------------------------------------------------------------
    | AI Credit Packages (for one-time purchase)
    |--------------------------------------------------------------------------
    */
    'credit_packages' => [
        ['credits' => 100,  'price' => 9.99,  'label' => '100 AI Credits'],
        ['credits' => 500,  'price' => 39.99, 'label' => '500 AI Credits'],
        ['credits' => 1000, 'price' => 69.99, 'label' => '1000 AI Credits'],
    ],
];
