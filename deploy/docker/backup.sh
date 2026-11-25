#!/bin/sh
# Gera uma cópia consistente do SQLite (VACUUM INTO) e escreve em stdout.
# Uso: docker compose exec -T app cachet-backup > backup.sqlite
set -eu

db="${DB_DATABASE:-/var/lib/cachet/database.sqlite}"
out="$(mktemp -u /tmp/cachet-backup.XXXXXX)"
trap 'rm -f "$out"' EXIT INT TERM

php -r '
$db = new SQLite3($argv[1]);
$db->busyTimeout(10000);
if (! $db->exec("VACUUM INTO '\''" . SQLite3::escapeString($argv[2]) . "'\''")) {
    fwrite(STDERR, $db->lastErrorMsg() . PHP_EOL);
    exit(1);
}
' -- "$db" "$out"

cat "$out"
