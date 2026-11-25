#!/bin/sh
# Atualiza o cachethq/core no composer.lock deste repositório, sem PHP no host.
# Usa o stage `base` do Dockerfile (PHP 8.4 e extensões iguais às da produção).
#
# Uso: ./deploy/update-core-lock.sh
set -eu

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
composer_bin="$(mktemp)"
trap 'rm -f "$composer_bin"' EXIT INT TERM

docker build --quiet --target base -t cachet-base:local -f "$app_dir/deploy/Dockerfile" "$app_dir" >/dev/null
docker run --rm --entrypoint cat composer:2 /usr/bin/composer > "$composer_bin"
chmod +x "$composer_bin"

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$app_dir":/app -w /app \
    -v "$composer_bin":/usr/local/bin/composer:ro \
    --entrypoint composer \
    cachet-base:local update cachethq/core --with-all-dependencies --no-interaction

echo
echo "cachethq/core agora em:"
grep -A8 '"name": "cachethq/core"' "$app_dir/composer.lock" | grep '"reference"' | head -1
