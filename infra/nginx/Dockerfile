FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY infra/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx backend/public/ /var/www/html/public/

RUN mkdir -p /var/www/html/storage/app/public \
    && ln -sfn ../storage/app/public /var/www/html/public/storage

EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
    CMD wget -qO- http://127.0.0.1:8080/up >/dev/null 2>&1 || exit 1
