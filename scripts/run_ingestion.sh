#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python=.venv/bin/python
collect() {
  "$python" ingestion/src/collecteur.py "$@"
}

docker compose build -q fournisseur
docker compose up -d --wait fournisseur
docker compose restart fournisseur > /dev/null
docker compose up -d --wait fournisseur
"$python" ingestion/tests/disponibilite.py
"$python" ingestion/tests/test_validation.py

collect --scenario clean --run clean-sequentiel --concurrence 1
collect --scenario clean --run clean-concurrent --concurrence 3
if collect --scenario panne --run panne --concurrence 3; then
  echo "le scenario panne aurait du echouer" >&2
  exit 1
fi
collect --scenario atelier --run atelier --concurrence 3

wc -l ingestion/data/valid/offres.jsonl ingestion/data/rejected/atelier.jsonl
