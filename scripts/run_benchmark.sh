#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_psql() {
  docker compose exec -T -e PGOPTIONS="-c client_min_messages=warning" postgres \
    psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket "$@"
}

docker compose up -d --wait postgres

row_count=$(run_psql -At -c \
  "SELECT CASE WHEN to_regclass('benchmark.benchmark_sales') IS NULL THEN 0
          ELSE (SELECT COUNT(*) FROM benchmark.benchmark_sales) END")
if [ "$row_count" -eq 0 ]; then
  run_psql < s3/generer.sql
fi
run_psql -At -c "SELECT COUNT(*) FROM benchmark.benchmark_sales" | grep -qx 10000000

run_psql -q -c "DROP INDEX IF EXISTS benchmark.benchmark_sales_store_id_idx"
run_psql -q -c "ANALYZE benchmark.benchmark_sales"

out=resultats/benchmark
mkdir -p "$out"
{
  echo "Date : $(date '+%Y-%m-%d %H:%M')"
  echo "Poste : $(uname -sm), Docker $(docker version --format '{{.Server.Version}}')"
  run_psql -At -c "SELECT version()"
  run_psql -At -c "SELECT 'shared_buffers = ' || current_setting('shared_buffers')
    || ', work_mem = ' || current_setting('work_mem')
    || ', max_parallel_workers_per_gather = '
    || current_setting('max_parallel_workers_per_gather')"
  echo "Limites du conteneur : 2 CPU, 2 Go de memoire (compose.yaml)"
} > "$out/0_contexte.txt"

run_psql -P pager=off -v phase="'sans index'" < sql/benchmark/measure.sql > "$out/1_sans_index.txt"
run_psql -P pager=off < sql/benchmark/create_index.sql > "$out/2_creation_index.txt"
run_psql -P pager=off -v phase="'avec index'" < sql/benchmark/measure.sql > "$out/3_avec_index.txt"
run_psql -P pager=off < sql/benchmark/analysis.sql > "$out/4_analyse.txt"

summarize() {
  awk -v phase="$2" '
    /^### / { label = $2; run = $4 }
    /Execution Time:/ && label != "" {
      gsub(/[^0-9.]/, "", $3); times[label, run] = $3; labels[label] = 1; label = ""
    }
    END {
      for (l in labels) {
        n = 0
        for (r = 2; r <= 4; r++) if ((l, r) in times) values[++n] = times[l, r]
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
          if (values[j] + 0 < values[i] + 0) { t = values[i]; values[i] = values[j]; values[j] = t }
        printf "| %s | %s | %s | %s | %s | %s | %s |\n", phase, l, times[l, 1], times[l, 2],
          times[l, 3], times[l, 4], values[2]
      }
    }' "$1"
}

{
  echo "| Phase | Requete | Passage 1 (ms) | Passage 2 | Passage 3 | Passage 4 | Mediane 2-4 (ms) |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
  summarize "$out/1_sans_index.txt" "sans index" | sort
  summarize "$out/3_avec_index.txt" "avec index" | sort
  summarize "$out/4_analyse.txt" "index force" | sort
} > "$out/resume_mesures.md"

cat "$out/resume_mesures.md"
