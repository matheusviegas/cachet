#!/bin/sh
set -eu

cd /app

if [ -z "${APP_KEY:-}" ]; then
    echo "ERRO: APP_KEY não definido. Gere com: echo \"base64:\$(openssl rand -base64 32)\"" >&2
    exit 1
fi

# Volumes novos ou atualizados podem não ter a estrutura esperada.
mkdir -p storage/app/public \
         storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/logs

if [ "${DB_CONNECTION:-sqlite}" = "sqlite" ]; then
    db_file="${DB_DATABASE:-/var/lib/cachet/database.sqlite}"
    [ -f "$db_file" ] || { touch "$db_file"; chmod 0600 "$db_file"; }
fi

# Migrations antes do optimize: o optimize grava no cache (tabela `cache`).
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    php artisan migrate --force --no-interaction
fi

# bootstrap/cache é tmpfs: gera manifests e caches de config/rotas/eventos/views
# a partir das variáveis de ambiente deste container.
php artisan optimize --no-interaction

exec "$@"
