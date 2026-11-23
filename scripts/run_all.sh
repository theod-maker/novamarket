#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_psql() {
  docker compose exec -T -e PGOPTIONS="-c client_min_messages=warning" postgres \
    psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket "$@"
}

docker compose up -d --wait postgres

run_psql -q < sql/01_schema.sql
run_psql -q < sql/02_import.sql

mkdir -p resultats
for step in 03_controls 04_indicators 05_anomalies; do
  run_psql -P pager=off < "sql/${step}.sql" > "resultats/${step}.txt"
  run_psql -P pager=off -P format=asciidoc -P footer=off < "sql/${step}.sql" \
    > "resultats/${step}.adoc"
  echo "resultats/${step}.txt resultats/${step}.adoc"
done
