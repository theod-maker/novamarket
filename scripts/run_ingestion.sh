#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose up -d --build --wait fournisseur
docker compose restart fournisseur
docker compose up -d --wait fournisseur

.venv/bin/python ingestion/tests/disponibilite.py
.venv/bin/python ingestion/tests/test_validation.py

.venv/bin/python ingestion/src/collecteur.py --scenario clean --run clean-sequentiel --concurrence 1
.venv/bin/python ingestion/src/collecteur.py --scenario clean --run clean-concurrent --concurrence 3
.venv/bin/python ingestion/src/collecteur.py --scenario panne --run panne \
  || echo "panne : echec attendu, aucun lot publie"
.venv/bin/python ingestion/src/collecteur.py --scenario atelier --run atelier
