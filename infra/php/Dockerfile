# syntax=docker/dockerfile:1.7

FROM php:8.4-fpm-alpine AS base

RUN apk add --no-cache \
        bash \
        curl \
        icu-libs \
        libzip \
        postgresql-client \
        su-exec \
    && apk add --no-cache --virtual .build-deps \
        icu-dev \
        libzip-dev \
        linux-headers \
        oniguruma-dev \
        postgresql-dev \
        $PHPIZE_DEPS \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        intl \
        mbstring \
        opcache \
        pcntl \
        pdo_pgsql \
        pgsql \
        zip \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/pear /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY infra/php/conf.d/99-smartbiz.ini /usr/local/etc/php/conf.d/99-smartbiz.ini
COPY infra/php/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY infra/php/entrypoint.sh /usr/local/bin/smartbiz-entrypoint

RUN addgroup -g 1000 -S appuser \
    && adduser -u 1000 -S appuser -G appuser \
    && chmod +x /usr/local/bin/smartbiz-entrypoint

WORKDIR /var/www/html
ENTRYPOINT ["smartbiz-entrypoint"]

FROM base AS development

RUN cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
USER appuser
EXPOSE 9000
CMD ["php-fpm", "-F"]

FROM base AS production

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

ENV APP_ENV=production \
    APP_DEBUG=false \
    DB_CONNECTION=sqlite \
    DB_DATABASE=:memory: \
    CACHE_STORE=array \
    SESSION_DRIVER=array \
    QUEUE_CONNECTION=sync

COPY --chown=appuser:appuser backend/composer.json backend/composer.lock ./
RUN composer install \
        --no-dev \
        --no-interaction \
        --no-progress \
        --prefer-dist \
        --optimize-autoloader \
        --classmap-authoritative \
        --no-scripts

COPY --chown=appuser:appuser backend/ ./

RUN mkdir -p \
        bootstrap/cache \
        storage/app/private \
        storage/app/public \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        /var/backups/smartbiz \
    && ln -sfn ../storage/app/public public/storage \
    && composer dump-autoload \
        --no-dev \
        --no-interaction \
        --optimize \
        --classmap-authoritative \
    && chown -R appuser:appuser /var/www/html /var/backups/smartbiz

USER appuser
EXPOSE 9000
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD php -r '$s=@fsockopen("127.0.0.1",9000); exit($s ? 0 : 1);'
CMD ["php-fpm", "-F"]
