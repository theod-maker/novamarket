#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose up -d --wait postgres

export NOVAMARKET_DSN="${NOVAMARKET_DSN:-host=127.0.0.1 port=15432 dbname=novamarket user=atelier}"
export PGPASSWORD="${PGPASSWORD:-$(docker compose exec -T postgres printenv POSTGRES_PASSWORD)}"
export DBT_ENV_SECRET_PASSWORD="$PGPASSWORD"
export DBT_DATABASE=novamarket

run_psql() {
  docker compose exec -T -e PGOPTIONS="-c client_min_messages=warning" postgres \
    psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket "$@"
}

run_dbt() {
  docker compose --profile transfo run --rm --no-deps --user "$(id -u):$(id -g)" -w /projet \
    -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
    dbt --no-use-colors "$@" --profiles-dir /work/profil
}

out=resultats/s4
mkdir -p "$out" s4/travail/profil
[ -f s4/travail/profil/profiles.yml ] \
  || cp transformation/dbt/profiles.exemple.yml s4/travail/profil/profiles.yml

run_psql -q -c "DROP SCHEMA IF EXISTS fournisseur CASCADE"

{
  echo "== 1er chargement =="
  .venv/bin/python transformation/chargement_postgres.py ingestion/data/valid/offres.jsonl
  echo
  echo "== 2e chargement du meme lot =="
  .venv/bin/python transformation/chargement_postgres.py ingestion/data/valid/offres.jsonl
  echo
  echo "== Lot avec erreurs de contenu =="
  .venv/bin/python transformation/chargement_postgres.py transformation/essais/offres_avec_erreurs.jsonl
  echo
  echo "== Lot qui echoue en base au milieu de la transaction =="
  .venv/bin/python transformation/chargement_postgres.py transformation/essais/offres_echec_milieu.jsonl \
    || echo "echec attendu"
  echo
  echo "== Offres en base apres les 4 passages =="
  run_psql -P pager=off -c "SELECT count(*) AS offres,
      count(*) FILTER (WHERE offer_id LIKE 'O9%') AS offres_de_test
    FROM fournisseur.offres"
} 2>&1 | tee "$out/1_chargement.txt"

run_dbt debug > "$out/2_dbt_debug.txt"
run_dbt compile > "$out/3_dbt_compile.txt"
run_dbt run > "$out/4_dbt_run.txt"
run_dbt build > "$out/5_dbt_build.txt"
run_dbt ls --resource-type model --select +mart_offres_fournisseurs --output name \
  > "$out/6_dbt_graphe.txt"
cp transformation/dbt/target/compiled/novamarket_dbt/models/marts/mart_offres_fournisseurs.sql \
  "$out/7_mart_compile.sql"

run_psql -P pager=off < sql/12_transformation_controls.sql > "$out/8_controles.txt"

tail -n 1 "$out/5_dbt_build.txt"
echo "preuves dans $out/"
