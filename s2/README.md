# NovaMarket S2 · poursuivre la base de S1

Reprenez votre base PostgreSQL de S1 et les choix de schéma de votre groupe. Les deux fichiers S2 complètent les ventes déjà importées. Ils utilisent les mêmes codes produit et n'ajoutent ni clients ni commandes.

## Démarrer et vérifier

Depuis `novamarket/` :

```bash
docker compose up -d --wait postgres
docker compose ps
docker compose exec postgres psql -X -U atelier -d novamarket
```

Dans `psql`, utilisez `SELECT current_database();`, `\dt` et `\d nom_table` pour retrouver la base, vos tables et leurs contraintes. Pour un client externe, le guide S1 contient les paramètres de connexion à `127.0.0.1:15432`. Si les ventes S1 manquent, sollicitez la base de reprise auprès du formateur.

## Sources à importer

CSV UTF-8 séparés par des virgules, avec en-têtes. Les dates sont au format `AAAA-MM-JJ`.

| Fichier | Colonnes et sens | Grain |
| --- | --- | --- |
| `donnees/categories.csv` | `category_id` code, `category_name` libellé, `parent_category_id` code du parent ou champ vide pour une racine. | Une catégorie du catalogue. |
| `donnees/products.csv` | `product_id` code partagé avec les lignes S1, `sku` référence commerciale, `product_name` libellé, `category_id` code de classement, `first_listed_on` date déclarée de première mise en vente. | Une fiche produit à la source, dont l'unicité reste à contrôler. |

Pour transférer les fichiers vers le client `psql` conteneurisé, quitter `psql` avec `\q` puis lancer ces commandes depuis `novamarket/` :

```bash
docker compose exec -T postgres mkdir -p /tmp/novamarket-s2
docker compose cp s2/donnees/. postgres:/tmp/novamarket-s2/
docker compose exec -T postgres ls -l /tmp/novamarket-s2
```

Créez vos tables de réception et utilisez `\copy` depuis `psql`. Gardez le brut disponible pour vos contrôles. Inspectez les champs vides, les identifiants et la couverture des codes produit de S1 avant d'intégrer le catalogue. Importez les catégories avant les produits. Décidez comment garantir l'intégrité des liens, en tenant compte de votre schéma S1 et des lignes qu'il contient déjà. Travaillez par transaction et vérifiez vos comptages avant de valider. Si vous utilisez des tables temporaires, gardez ouverte la session qui les a créées.

## Missions S2

| Mission | Travail du groupe |
| --- | --- |
| **M1 — Enrichissement** | Intégrer le catalogue dans la base S1 et vérifier la couverture des codes produit. Examiner les multiplicités à la réception avant d'ajouter des contraintes ou de joindre les ventes. |
| **M2 — Classements** | Classer les produits et les clients selon leurs performances commerciales. Justifier les groupes de comparaison et le traitement des ex æquo. Mesurer l'effet de duplications sur au moins un classement. |
| **M3 — Évolution** | Comparer les ventes entre périodes avec `LAG()` et `LEAD()`. Contrôler la couverture des périodes et la cohérence des dates entre ventes et catalogue. Distinguer une évolution inhabituelle d'une incohérence démontrée. |
| **M4 — Segmentation** | Segmenter les clients selon leurs performances avec `NTILE()`. Expliciter la population, la mesure, l'ordre et le traitement des égalités. |
| **M5 — CTE récursive** | Parcourir la hiérarchie des catégories avec `WITH RECURSIVE` et consolider un indicateur par branche pour comparer les familles du catalogue. Contrôler les rattachements et le risque de double comptage. |

Consignez le grain, le périmètre de vente et les limites d'interprétation avec chaque résultat. Les décisions d'analyse et les requêtes sont à construire en groupe.

## Exemple indépendant et dépannage

Depuis `novamarket/`, exécutez la démonstration sur des grandeurs d'atelier, sans tables permanentes :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/exemple.sql
```

Sous Windows, exécutez ces commandes dans le terminal WSL2. Si un fichier manque dans le conteneur après sa recréation, refaites la copie. Si le service est indisponible, consultez `docker compose logs --tail=50 postgres`. Si un import échoue, vérifiez les noms et types avec `\d`, confirmez le chemin et l'en-tête, puis annulez la transaction en échec avec `ROLLBACK;`. En cas d'erreur de clé, inspectez la réception avant de relancer. [Guide S1](../s1/DEMARRAGE.md) · [Référence SQL](../REFERENCE_SQL.md)
