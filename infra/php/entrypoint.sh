#!/bin/sh
set -eu

cd /var/www/html

mkdir -p \
    bootstrap/cache \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs

if [ "${APP_ENV:-production}" = "production" ] && [ "${SMARTBIZ_OPTIMIZE_ON_START:-true}" = "true" ]; then
    php artisan optimize --no-interaction
fi

exec "$@"
