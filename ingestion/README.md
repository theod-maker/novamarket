# S3 · Ingestion asynchrone

## Préparer

Depuis `novamarket/`, avec Python **3.12** disponible :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-v3.txt
docker compose up -d --build --wait fournisseur
python ingestion/tests/disponibilite.py
python ingestion/exemple.py
```

Avec `uv`, on peut utiliser `uv venv --python 3.12 --seed .venv` en l'absence de cette version locale. Ne pas distribuer le venv. L'exemple sur des cuves illustre session, semaphore, timeout, retry, logger et gather. Développer le collecteur fournisseur dans `ingestion/src/`.

## Contrat HTTP

`GET /health` retourne `{"status":"ok"}`. `GET /offers?page=1&scenario=atelier&run=groupe01-essai01` retourne `page`, `total_pages`, `next_page` (nul à la fin) et une liste `items`. Exemple de sondage indépendant du collecteur :

```bash
curl -fsS 'http://127.0.0.1:18080/offers?page=1&scenario=clean&run=sonde'
```

| Champ | Contrat |
| --- | --- |
| `offer_id`, `supplier_id` | Identifiants texte stables. Les fournisseurs de simulation sont F01, F02 et F03. |
| `product_id` | Entier parmi les produits du catalogue S2. |
| `price_cents`, `available_units` | Entiers non négatifs, centimes et unités; `currency` vaut EUR. |
| `observed_on` | Jour ISO AAAA-MM-JJ. |

Six pages de quatre enregistrements. Choisir un `run` neuf pour rejouer les premières tentatives. `clean` fournit le contrôle sans fautes. `atelier` injecte réponses transitoires (429 avec `Retry-After`, JSON invalide, délai) et anomalies métier. `panne` produit une erreur permanente. La latence de base se règle par `NOVAMARKET_API_LATENCY`. Comparer les collectes avec le même scénario et la même latence. Borner le nombre d'essais et la concurrence. Compter les essais HTTP et les lignes séparément.

## Sorties et reprise

Une exécution complète produit des fichiers UTF-8 JSONL à raison d'un objet par ligne. `data/raw/` garde les pages reçues; `data/valid/offres.jsonl` conserve les champs du contrat; `data/rejected/` conserve page, position, motif et objet brut. Le bilan distingue pages reçues, lignes examinées, valides et rejetées, reprises et durée. Prévoir un nouveau répertoire par essai ou un archivage explicite. Un lot incomplet ne doit pas être publié comme valide. Utiliser l'[entrée validée S4](../transformation/secours/offres.jsonl) si le collecteur doit être repris.

Si le port est pris, ajuster `NOVAMARKET_API_PORT` à la fois pour Compose et le shell. Examiner `docker compose logs fournisseur`. L'API fonctionne seule si les travaux SQL S2 sont incomplets. Le formateur peut préparer le catalogue canonique pour la validation et le chargement suivants.
