# NovaMarket S1–S3 : base PostgreSQL, analyses SQL, benchmark et ingestion

Ce projet charge les fichiers NovaMarket dans PostgreSQL, garde la trace des lignes rejetées,
calcule les indicateurs de ventes (S1), intègre le catalogue et fait les analyses avancées (S2),
puis mesure l'effet d'un index sur un jeu de 10 millions de lignes (benchmark). En S3, un collecteur
Python asynchrone récupère les offres d'une API fournisseur et sépare offres valides et rejets.

## Exécution

Prérequis : Docker et Docker Compose, plus Python 3.12 pour S3. Toutes les commandes se lancent
depuis ce dossier.

```bash
./scripts/run_all.sh        # S1 + S2 : schéma, imports, catalogue, indicateurs, analyses
./scripts/run_benchmark.sh  # benchmark : génération si besoin, mesures avant/après index
./scripts/run_ingestion.sh  # S3 : API fournisseur, collecte clean, panne et atelier
```

Pour S3, créer d'abord l'environnement Python (une seule fois) :

```bash
uv venv --python 3.12 --seed .venv   # ou : python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements-v3.txt
```

`run_all.sh` démarre PostgreSQL, copie `s2/donnees/` dans le conteneur, recrée les schémas
`reception`, `quality` et `core`, importe toutes les sources, puis écrit les sorties dans `resultats/`.
Il repart toujours des fichiers bruts : le relancer redonne exactement les mêmes résultats. Il ne touche
pas au schéma `benchmark`.

`run_benchmark.sh` lance `s3/generer.sql` seulement si `benchmark.benchmark_sales` est absente
(environ 4 s, 500 Mo), vérifie les 10 000 000 lignes, supprime l'index de test, mesure, crée l'index,
mesure à nouveau et écrit les plans dans `resultats/benchmark/`.

`run_ingestion.sh` démarre l'API `fournisseur` (port 18080), lance les tests de validation, puis
quatre collectes : `clean` en séquentiel et en concurrent, `panne` (doit échouer sans publier) et
`atelier`. Les sorties vont dans `ingestion/data/`. Une collecte seule :

```bash
.venv/bin/python ingestion/src/collecteur.py --scenario atelier --run essai01 --concurrence 3
```

Connexion manuelle :

```bash
docker compose exec postgres psql -X -U atelier -d novamarket
```

Depuis un éditeur SQL sur l'hôte : `127.0.0.1:15432`, base `novamarket`, utilisateur `atelier`. Si le
port ou le sous-réseau sont déjà pris, voir `SAUVEGARDE_SQL.md` (`NOVAMARKET_PG_PORT`,
`NOVAMARKET_SUBNET`).

## Organisation

| Chemin | Contenu |
| --- | --- |
| `s1/`, `s2/`, `s3/` | kits fournis : sources brutes (jamais modifiées), exemples, générateur du benchmark |
| `sql/01_schema.sql` | S1 : schémas `reception`, `quality`, `core` et contraintes |
| `sql/02_import.sql` | S1 : chargement brut, contrôles, rejets, intégration |
| `sql/03_controls.sql` | S1 : volumes reçus, intégrés et rejetés, journal des rejets |
| `sql/04_indicators.sql` | S1 : statuts, clients sans commande, CA, panier moyen, rapprochement |
| `sql/05_anomalies.sql` | S1 : doublon, faux doublons de paiement, jointure qui multiplie, statuts |
| `sql/06_catalog.sql` | S2 : tables et import des catégories et produits, clé étrangère produit |
| `sql/07_catalog_controls.sql` | S2 : volumes, doublon, couverture des codes, cohérence des dates |
| `sql/08_rankings.sql` | S2 : `RANK`, `DENSE_RANK`, ex aequo, effet d'une duplication |
| `sql/09_evolution.sql` | S2 : `LAG`, `LEAD`, couverture des périodes |
| `sql/10_segmentation.sql` | S2 : `NTILE(4)`, population, égalités |
| `sql/11_hierarchy.sql` | S2 : `WITH RECURSIVE`, cycles, CA par famille, double comptage |
| `sql/benchmark/` | mesures, création de l'index, analyses du benchmark |
| `ingestion/api/` | S3 : API fournisseur simulée (fournie) |
| `ingestion/src/` | S3 : collecteur, validation, journalisation |
| `ingestion/tests/` | S3 : test de disponibilité (fourni), tests des règles de validation |
| `ingestion/data/` | S3 : `raw/`, `valid/offres.jsonl`, `rejected/`, `logs/`, `bilans/` |
| `docs/modele.md` | S1 : grain, schéma annoté, choix justifiés |
| `docs/anomalies.md` | S1 : tableau anomalie, détection, effet, décision |
| `docs/catalogue.md` | S2 : intégration du catalogue et anomalies |
| `docs/analyses.md` | S2 : résultats et limites des analyses avancées |
| `docs/benchmark.md` | S2 : protocole, mesures, index efficace et inefficace, estimations |
| `docs/contrat_api.md` | S3 : endpoints, pagination, champs, comparaison des scénarios |
| `docs/ingestion.md` | S3 : concurrence, reprises, règles de validation, bilans, limites |
| `resultats/` | sorties de la dernière exécution : `.adoc` (tableaux lisibles sur GitHub) et `.txt` |

## Volumes

| Source | Reçues | Intégrées | Rejetées |
| --- | --- | --- | --- |
| customers.csv | 180 | 180 | 0 |
| orders.csv | 400 | 400 | 0 |
| order_items.csv | 802 | 800 | 2 (1 doublon exact, 1 commande inexistante) |
| payments.ndjson | 480 | 480 | 0 |
| categories.csv | 10 | 10 | 0 |
| products.csv | 25 | 24 | 1 (doublon exact du produit 3) |
| benchmark.benchmark_sales | 10 000 000 générées | | |
| API offres, scénario `atelier` | 24 | 20 | 4 (champ manquant, prix invalide, produit inexistant, doublon) |

## Résultats principaux

| Sujet | Résultat | Détail |
| --- | --- | --- |
| CA des commandes terminées | 26 210,00 € pour 320 commandes | égal aux paiements encaissés |
| Panier moyen | 81,91 € | CA / nombre de commandes terminées |
| Meilleur produit | produit 23, 2 733,75 € | `docs/analyses.md` |
| Évolution mensuelle | -39,3 % en novembre, mais -0,9 % par jour | novembre incomplet (19 jours) |
| Quartiles clients | le 1er quart fait 35,4 % du CA | 120 clients avec commande terminée |
| Familles | Loisirs 68,5 %, Maison 31,5 % | somme des niveaux = 2,6 fois le total |
| Index sur `store_id` | 123 ms → 0,02 ms pour 100 lignes ; aucun gain pour 95 % des lignes | `docs/benchmark.md` |
| Collecte des offres | 0,76 s en séquentiel, 0,38 s avec 3 appels simultanés | `docs/ingestion.md` |
| Scénario `atelier` | 9 requêtes pour 6 pages (3 reprises), 20 offres publiées | 429, JSON invalide, timeout |

Hypothèses : le chiffre d'affaires se limite aux commandes `completed` ; le montant d'une ligne est le
prix unitaire de la transaction ; on agrège chaque table avant de joindre, pour ne pas multiplier les
lignes.

## État et limites

- S1 (M1 à M5), S2 (catalogue, classements, évolution, segmentation, hiérarchie, benchmark) et S3
  (M1 à M4, ingestion asynchrone) faits.
- S3 : le scénario `panne` s'arrête sans publier de lot ; les offres valides restent hors de
  PostgreSQL, leur chargement est prévu en S4.
- Commandes annulées avec 3 283,75 € encaissés : aucun remboursement dans les sources, à confirmer avec
  NovaMarket.
- Produit 6 vendu avant sa date de mise en vente déclarée : ventes conservées, date du catalogue à
  vérifier.
- Contrôles d'import limités aux anomalies rencontrées (doublons, statuts, références inexistantes) :
  une valeur mal typée (texte dans une quantité) arrêterait l'import au lieu d'être rejetée.
- Benchmark mesuré sur un seul poste, sans démarrage à froid : voir les limites dans `docs/benchmark.md`.
- Approfondissement S1 A1 (normalisation du planning) : non traité.
