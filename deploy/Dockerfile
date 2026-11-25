# syntax=docker/dockerfile:1.7

# Build a partir da raiz do fork do app (context: .. no docker-compose.yml).
# A imagem tem o código do checkout atual; o composer.lock fixa o commit do core.
ARG FRANKENPHP_IMAGE=dunglas/frankenphp:1.14-php8.4-trixie
ARG COMPOSER_IMAGE=composer:2

FROM ${COMPOSER_IMAGE} AS composer

# -----------------------------------------------------------------------------
# base: PHP + extensões exigidas pelo Cachet/Laravel/Filament
# -----------------------------------------------------------------------------
FROM ${FRANKENPHP_IMAGE} AS base

RUN set -eux; \
    install-php-extensions bcmath intl pcntl zip gd opcache; \
    rm -rf /var/lib/apt/lists/* /tmp/*

# -----------------------------------------------------------------------------
# build: copia o código, instala dependências e publica assets
# -----------------------------------------------------------------------------
FROM base AS build

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git unzip; \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_HOME=/tmp/composer

# O .dockerignore da raiz deixa de fora vendor, node_modules, .git e os .env.
COPY . /app
WORKDIR /app

# Instala exatamente o que está no composer.lock do fork do app.
RUN set -eux; \
    composer install --no-dev --prefer-dist --optimize-autoloader; \
    php artisan vendor:publish --tag=cachet --ansi; \
    php artisan vendor:publish --tag=cachet-assets --force --ansi; \
    php artisan filament:assets --ansi; \
    ln -sfn ../storage/app/public public/storage; \
    # Remove o que não é necessário em runtime
    rm -rf deploy .dockerignore tests .github .agents .amp art .git* .editorconfig phpunit.xml \
           bootstrap/cache/*.php storage/logs/* /tmp/composer

# -----------------------------------------------------------------------------
# runtime
# -----------------------------------------------------------------------------
FROM base AS runtime

ARG APP_UID=10001
ARG APP_GID=10001

COPY deploy/docker/php.ini "$PHP_INI_DIR/conf.d/zz-cachet.ini"
COPY deploy/docker/Caddyfile /etc/frankenphp/Caddyfile
COPY --chmod=0755 deploy/docker/entrypoint.sh /usr/local/bin/cachet-entrypoint
COPY --chmod=0755 deploy/docker/backup.sh /usr/local/bin/cachet-backup

# Código pertence ao root e fica somente-leitura para o usuário da aplicação.
COPY --from=build --chown=root:root /app /app

RUN set -eux; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    groupadd --gid "${APP_GID}" cachet; \
    useradd --uid "${APP_UID}" --gid cachet --no-create-home \
            --home-dir /nonexistent --shell /usr/sbin/nologin cachet; \
    # A porta 8080 não é privilegiada: remove a file capability do binário.
    # Sem isso o exec falha com cap_drop: [ALL] + no-new-privileges.
    setcap -r /usr/local/bin/frankenphp; \
    mkdir -p /var/lib/cachet \
             /app/storage/app/public \
             /app/storage/framework/cache/data \
             /app/storage/framework/sessions \
             /app/storage/framework/views \
             /app/storage/logs; \
    # Apenas os diretórios de dados/cache são graváveis pelo usuário cachet.
    chown -R cachet:cachet /app/storage /app/bootstrap/cache /var/lib/cachet \
                           /data/caddy /config/caddy; \
    chmod -R u=rwX,g=rX,o= /app/storage /app/bootstrap/cache /var/lib/cachet

ENV APP_ENV=production \
    APP_DEBUG=false \
    CACHET_DOCKER=true \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/var/lib/cachet/database.sqlite \
    LOG_CHANNEL=stderr \
    RUN_MIGRATIONS=false

USER cachet:cachet
WORKDIR /app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8080/up || exit 1

ENTRYPOINT ["/usr/local/bin/cachet-entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]
