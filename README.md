# NovaMarket S1 : SQL relationnel et premiers indicateurs

Base PostgreSQL fiable construite à partir des sources NovaMarket, journal des rejets et
indicateurs commerciaux reproductibles.

## Exécution

Prérequis : Docker et Docker Compose. Depuis ce dossier :

```bash
./scripts/run_all.sh
```

Le script démarre PostgreSQL, recrée les schémas, importe les sources dans une seule transaction,
puis écrit les sorties dans `resultats/`. Il peut être relancé : il repart toujours d'une base vide.

Connexion manuelle :

```bash
docker compose exec postgres psql -X -U atelier -d novamarket
```

Depuis un éditeur SQL sur l'hôte : `127.0.0.1:15432`, base `novamarket`, utilisateur `atelier`.

## Organisation

| Chemin | Contenu |
| --- | --- |
| `s1/donnees/` | sources brutes, jamais modifiées (montées en lecture seule) |
| `sql/01_schema.sql` | schémas `reception`, `quality`, `core` et contraintes |
| `sql/02_import.sql` | chargement brut, contrôles ligne à ligne, rejets, intégration |
| `sql/03_controls.sql` | volumes reçus, intégrés et rejetés, journal des rejets, cohérence |
| `sql/04_indicators.sql` | indicateurs M3 |
| `sql/05_anomalies.sql` | démonstrations M4 |
| `docs/modele.md` | M1 : grain, schéma annoté, choix justifiés |
| `docs/anomalies.md` | M4 : tableau anomalie, détection, effet, décision |
| `resultats/` | sorties de la dernière exécution |

## Volumes

| Source | Reçues | Intégrées | Rejetées |
| --- | --- | --- | --- |
| customers.csv | 180 | 180 | 0 |
| orders.csv | 400 | 400 | 0 |
| order_items.csv | 802 | 800 | 2 (1 doublon exact, 1 commande orpheline) |
| payments.ndjson | 480 | 480 | 0 |

## Indicateurs principaux

| Indicateur | Valeur | Définition |
| --- | --- | --- |
| Commandes | 320 completed, 40 pending, 40 cancelled | une ligne par commande |
| Clients sans commande | 30 sur 180 | `NOT EXISTS` sur les commandes |
| Montant des lignes des commandes terminées | 26 210,00 € | somme `quantity * unit_price_cents`, statut `completed` |
| Panier moyen | 81,91 € | montant ci-dessus / 320 commandes terminées |
| Paiements encaissés des commandes terminées | 26 210,00 € | égal au montant des articles pour les 320 commandes |

Hypothèses : le chiffre d'affaires se limite aux commandes `completed` ; le montant d'une ligne est
le prix unitaire de la transaction ; les montants sont agrégés par commande avant toute jointure
entre articles et paiements.

## État et limites

- Socle M1 à M5 fait : schéma, imports vérifiables, indicateurs, tableau d'anomalies.
- Commandes annulées avec 3 283,75 € encaissés : aucun remboursement dans les sources, point à
  confirmer avec NovaMarket.
- Catalogue (`products.csv`, `categories.csv`) non intégré : hors périmètre S1.
- A1 (normalisation, variantes de jointure) : à faire.
