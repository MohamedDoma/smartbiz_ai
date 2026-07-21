#!/bin/sh
set -eu

cd /var/www/html

require_value() {
    name="$1"
    eval "value=\${$name:-}"
    [ -n "$value" ] || {
        echo "Missing required environment variable: $name" >&2
        exit 1
    }
}

if [ "${APP_ENV:-production}" = "production" ]; then
    case "${SMARTBIZ_CONTAINER_ROLE:-application}" in
        application|application-scheduler)
            require_value DB_USERNAME
            require_value DB_PASSWORD
            require_value DB_TENANT_USERNAME
            require_value DB_TENANT_PASSWORD
            [ "$DB_USERNAME" != "$DB_TENANT_USERNAME" ] || {
                echo "Control and tenant runtime database users must differ in production." >&2
                exit 1
            }
            [ -z "${DB_OWNER_PASSWORD:-}" ] || {
                echo "Owner credentials must not be injected into application containers." >&2
                exit 1
            }
            [ -z "${DB_BACKUP_PASSWORD:-}" ] || {
                echo "Backup credentials must not be injected into application containers." >&2
                exit 1
            }
            ;;
        backup-scheduler)
            require_value DB_BACKUP_USERNAME
            require_value DB_BACKUP_PASSWORD
            [ "${DB_CONNECTION:-}" = "pgsql_backup" ] || {
                echo "Backup scheduler must use pgsql_backup as its default database connection." >&2
                exit 1
            }
            [ -z "${DB_OWNER_PASSWORD:-}" ] || {
                echo "Owner credentials must not be injected into the backup scheduler." >&2
                exit 1
            }
            [ -z "${DB_PASSWORD:-}" ] || {
                echo "Control credentials must not be injected into the backup scheduler." >&2
                exit 1
            }
            [ -z "${DB_TENANT_PASSWORD:-}" ] || {
                echo "Tenant runtime credentials must not be injected into the backup scheduler." >&2
                exit 1
            }
            ;;
        operations)
            require_value DB_OWNER_USERNAME
            require_value DB_OWNER_PASSWORD
            require_value DB_BACKUP_USERNAME
            require_value DB_BACKUP_PASSWORD
            ;;
    esac
fi

mkdir -p \
    bootstrap/cache \
    storage/app/private \
    storage/app/public \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    "${BACKUP_PATH:-/var/backups/smartbiz}"

if [ "${APP_ENV:-production}" = "production" ] && [ "${SMARTBIZ_OPTIMIZE_ON_START:-true}" = "true" ]; then
    php artisan optimize --no-interaction
fi

exec "$@"
