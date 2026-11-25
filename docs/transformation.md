# S4 : Chargement PostgreSQL et transformations dbt

## Fonctionnement

```
ingestion/data/valid/offres.jsonl ──chargement_postgres.py──► fournisseur.offres
                                                                     │
                            core.products, categories, orders, order_items (S1-S2)
                                                                     │
                                                                    dbt
        staging (vues) ──► intermediate (éphémère) ──► mart (table) dans le schéma dbt_dev
```

| Fichier | Rôle |
| --- | --- |
| `transformation/chargement_postgres.py` | lecture du JSONL, contrôles, chargement en une transaction, bilan |
| `transformation/essais/` | deux lots de test : erreurs de contenu, échec en base au milieu du lot |
| `transformation/dbt/` | projet dbt unique (monté sur `/projet` dans le conteneur) |
| `sql/12_transformation_controls.sql` | comparaisons de volumes et de totaux après dbt |
| `scripts/run_transformation.sh` | rejoue toute la S4 et écrit les preuves dans `resultats/s4/` |

## M1 : Chargement des offres

**Schéma et grain.** Les offres vont dans un schéma séparé, `fournisseur`, pour ne pas mélanger
les données d'un fournisseur externe avec les tables validées de `core`. Une ligne correspond à une
offre (`offer_id`) observée à une date (`observed_on`). La clé primaire est donc
`(offer_id, observed_on)` : la même offre pourra être observée plusieurs jours sans conflit.

**Contrôles avant insertion.** Champs présents, produit existant dans `core.products`, fournisseur
connu (F01 à F03), devise `EUR`, prix et unités entiers positifs, date valide. Une offre qui échoue
est rejetée avec son motif ; les autres sont chargées.

**Transaction et rejeu.** Tout le lot est écrit dans une seule transaction (`with psycopg.connect`) :
une erreur en base annule tout. Avec `ON CONFLICT DO NOTHING`, une offre déjà présente pour la même
date est ignorée. Le bilan sépare les offres insérées, déjà présentes et rejetées.

| Passage | Lues | Insérées | Déjà présentes | Rejetées |
| --- | --- | --- | --- | --- |
| 1er chargement | 20 | 20 | 0 | 0 |
| 2e chargement du même lot | 20 | 0 | 20 | 0 |
| Lot avec erreurs | 4 | 0 | 1 | 3 (produit inconnu, fournisseur inconnu, date invalide) |
| Lot qui échoue en base | 2 | 0 | 0 | lot annulé (`integer out of range`) |

Dans le dernier lot, la première offre (O904) est valide et passe l'`INSERT`, mais la seconde a un
prix trop grand pour un `integer`. PostgreSQL refuse, la transaction est annulée et O904 n'est pas en
base : 20 offres au total, 0 offre de test.

## M2 et M3 : Sources et staging

Les sources sont déclarées dans `models/staging/sources.yml` : `fournisseur.offres` et les tables
`core` de S1-S2. Chaque modèle staging lit une seule source avec `source()` et garde son grain
(une ligne en entrée = une ligne en sortie). On y harmonise seulement les types et les noms :
prix converti en euros (`price_eur`), `trim` sur les libellés, montant de ligne calculé.

| Modèle | Grain | Lignes |
| --- | --- | --- |
| `stg_offres` | une offre à une date | 20 |
| `stg_produits` | un produit | 24 |
| `stg_categories` | une catégorie | 10 |
| `stg_commandes` | une commande | 400 |
| `stg_lignes_commande` | une ligne de commande | 800 |

## M4 : Intermediate et mart

**`int_ventes_par_produit`** (éphémère) : une ligne par produit, sur les commandes `completed`
seulement : unités vendues, CA, prix moyen de vente. On agrège les lignes de commande **avant** de
les joindre aux offres. Une jointure directe offres x lignes de commande donnerait 666 lignes au lieu
de 20.

**`mart_offres_fournisseurs`** (table) : même grain que `stg_offres`, une offre à une date. Chaque
offre est complétée par le produit, la catégorie et les ventes du produit, pour comparer le prix
proposé par le fournisseur au prix moyen de vente (`price_gap_eur`). Jointures :

- `stg_produits` et `stg_categories` en `JOIN` : une offre a toujours un produit (contrôlé au
  chargement et par un test `relationships`), un produit a une seule catégorie ;
- `int_ventes_par_produit` en `LEFT JOIN` : une offre sur un produit jamais vendu reste dans le mart
  avec `units_sold = 0`.

**Matérialisations** (réglées par dossier dans `dbt_project.yml`) :

| Couche | Choix | Raison |
| --- | --- | --- |
| staging | `view` | toujours à jour, peu de lignes, on peut l'interroger dans `psql` |
| intermediate | `ephemeral` | utilisé par un seul modèle ; dbt l'insère en CTE, rien n'est créé en base |
| marts | `table` | résultat final lu par les analyses, calculé une fois à chaque `dbt run` |

Dans `resultats/s4/7_mart_compile.sql`, on voit `int_ventes_par_produit` devenu
`WITH __dbt__cte__int_ventes_par_produit AS (...)`. Dans la base, `dbt_dev` contient 5 vues et
1 table, pas d'objet pour l'intermediate.

## M5 : Vérification

`dbt build` exécute les modèles et 29 tests : 35 étapes, toutes réussies.

| Test | Vérifie |
| --- | --- |
| `unique`, `not_null` | clés des sources et des modèles staging |
| `accepted_values` | devise `EUR`, statuts de commande |
| `relationships` | chaque offre pointe vers un produit du catalogue |
| `tests/mart_offres_cle_unique.sql` | une seule ligne par `(offer_id, observed_on)` dans le mart |
| `tests/mart_offres_sans_multiplication.sql` | mêmes lignes et mêmes unités dans la source et le mart |
| `tests/ventes_egales_a_core.sql` | CA de l'intermediate = CA des commandes terminées de S1 (26 210,00 €) |

Les deux tests du mart ont été vérifiés en cassant la jointure exprès (lignes de commande jointes
sans agrégation) : ils échouent bien (20 clés en double, volumes différents).

| Contrôle | Source | Staging | Mart |
| --- | --- | --- | --- |
| Offres | 20 | 20 | 20 |
| Unités disponibles | 488 | 488 | 488 |
| Unités vendues des produits offerts | 1 039 (core) | | 1 039 |

Rejouer `scripts/run_transformation.sh` repart d'un schéma `fournisseur` vide et redonne les mêmes
chiffres.

## Résultats

| Fournisseur | Offres | Unités disponibles | Valeur des offres | Unités vendues |
| --- | --- | --- | --- | --- |
| F01 | 7 | 164 | 4 160,00 € | 372 |
| F02 | 6 | 156 | 4 065,00 € | 480 |
| F03 | 7 | 168 | 3 990,00 € | 187 |

Les produits 5, 10, 17 et 24 n'ont pas d'offre : leurs offres ont été rejetées en S3 ou absentes de
l'API.

## Limites

- Une seule date d'observation (2026-11-24) : la clé gère plusieurs dates, mais ce n'est pas encore
  testé sur de vraies données.
- Le prix fournisseur est égal au prix moyen de vente pour tous les produits (`price_gap_eur = 0`) :
  données simulées, aucune marge n'est mesurable.
- Le script `s4/preparer_reception.sql` cité dans le README du kit n'était pas fourni : les variantes
  d'anomalies de réception (`quantity_text`, etc.) ne sont pas traitées.
- Le mot de passe local est lu dans le conteneur PostgreSQL par le script ; il n'est écrit dans
  aucun fichier du dépôt. Le profil dbt est dans `s4/travail/`, ignoré par Git.
