# S2 M1 : intégration du catalogue

Scripts : `sql/06_catalog.sql` (tables et import), `sql/07_catalog_controls.sql` (contrôles).
Résultats : `resultats/07_catalog_controls.txt`.

## Grain et relations

| Source | Une ligne représente | Clé | Relations |
| --- | --- | --- | --- |
| `categories.csv` | une catégorie | `category_id` | `parent_category_id` pointe vers une autre catégorie de la même table (vide pour une racine) |
| `products.csv` | une fiche produit | `product_id` (unicité à contrôler) | `category_id` vers `categories` ; `product_id` est le code utilisé dans `order_items` |

Ordre d'import : catégories, puis produits, puis ajout de la clé étrangère
`order_items.product_id → products.product_id`.

## Tables créées

Même principe qu'en S1 : réception en `text`, journal `quality.rejected_rows`, tables propres dans `core`.

- `core.categories` : `parent_category_id` référence `core.categories` (auto-référence) et un `CHECK`
  interdit qu'une catégorie soit son propre parent.
- `core.products` : `product_id` clé primaire, `sku` unique, `category_id` obligatoire et référencé.
- `core.order_items` : la contrainte `order_items_product_id_fkey` est ajoutée après l'import, une fois
  la couverture des codes vérifiée (0 ligne sans fiche). Toute future ligne de vente avec un code
  produit inconnu sera refusée.

## Comptages

| Source | Reçues | Intégrées | Rejetées |
| --- | --- | --- | --- |
| categories.csv | 10 | 10 | 0 |
| products.csv | 25 | 24 | 1 |

## Anomalies

| Anomalie | Détection | Effet | Décision |
| --- | --- | --- | --- |
| Produit 3 présent deux fois (lignes de données 3 et 25, fiches identiques) | `GROUP BY product_id` avec `MIN(source_row)` ; contrôle C3 : une seule version distincte | Joindre les ventes au catalogue brut double les lignes du produit 3 : son CA passe de 236,25 € à 472,50 € et le CA total de 26 210,00 € à 26 446,25 € (voir `08_rankings`, R4) | 2e fiche rejetée (`doublon`) |
| Produit 6 vendu avant sa date de mise en vente (déclarée le 15/09/2026, première vente le 01/09/2026) | contrôle C6 : `ordered_on < first_listed_on` | 6 lignes de commande concernées, dont 5 dans des commandes terminées (62,50 € en septembre) | Ventes conservées : les commandes existent et 5 sur 6 sont terminées. C'est la date du catalogue qui paraît fausse, à signaler à NovaMarket |
| Aucun code produit vendu sans fiche | contrôle C4 | aucun | clé étrangère ajoutée |
| Aucun produit du catalogue sans vente | contrôle C4 bis | aucun | rien |
| Produits rattachés uniquement à des catégories feuilles | contrôle C5 | pas de risque de mélange entre niveaux | rien |
| Hiérarchie sans cycle ni catégorie isolée | `11_hierarchy`, H2 : 10 catégories atteintes sur 10, profondeur max 2 | aucun | rien |
