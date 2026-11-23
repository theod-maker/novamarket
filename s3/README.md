# NovaMarket S3 · benchmark PostgreSQL

## Démarrage et génération en FFP

Lancer les commandes depuis `novamarket/`, dans Bash, zsh ou WSL2. Reprendre la base du groupe sur le même volume Docker. Remplacer `novamarket` si le groupe utilise un autre nom de base.

```bash
docker compose up -d --wait postgres
docker compose ps
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s3/generer.sql
```

Le script ajoute le schéma `benchmark` dans une transaction. Vérifier la sortie `COMMIT`. Une deuxième exécution rencontre le schéma existant et revient en arrière. Si la génération a déjà abouti, passer directement aux contrôles. Le script est déterministe et rassemble toutes les données de benchmark dans ce schéma.

Dans un autre terminal ou après la génération, ouvrir `psql` avec `docker compose exec postgres psql -X -U atelier -d novamarket` puis vérifier :

```sql
SELECT current_database();
\dt benchmark.*
\d benchmark.benchmark_sales
SELECT count(*) FROM benchmark.benchmark_sales;
SELECT pg_size_pretty(pg_total_relation_size('benchmark.benchmark_sales'));
```

Le comptage exact doit donner 10 000 000. Le comptage parcourt la table. Pour suivre la charge sur un autre terminal, utiliser `docker stats` et repérer le service PostgreSQL. Les utilisateurs d'un client externe retrouvent les paramètres dans le [guide S1](../s1/DEMARRAGE.md).

| Relation | Grain et champs |
| --- | --- |
| `benchmark.benchmark_sales` | Une vente simulée par `sale_id`, avec `sold_on`, `store_id`, `zone_id`, `channel_id` et `amount_cents`. Les fréquences par magasin sont inégales. |
| `benchmark.campaign_assignments` | Une association entre `store_id` et `campaign_id`. Un magasin peut appartenir à plusieurs campagnes. |

Les identifiants de ces simulations appartiennent à un jeu séparé. Les chiffres du benchmark ne s'ajoutent pas aux indicateurs S1–S2.

## Lire les plans et mesurer

- Commencer par `EXPLAIN` pour lire le plan estimé. Puis utiliser `EXPLAIN (ANALYZE, BUFFERS)` sur la requête de lecture. `ANALYZE` dans cette commande exécute la requête.
- Lire les nœuds enfants puis leurs parents. Repérer scans séquentiels, accès par index, agrégations, tris et jointures. Les valeurs `cost` sont des unités de coût estimées. Les lignes `Planning Time` et `Execution Time` sont en millisecondes.
- Sur un même nœud, comparer `rows` estimé avec `actual rows`. Avec plusieurs boucles, `actual rows` est une moyenne par boucle, arrondie dans le plan texte. Lire aussi `loops` et les workers. Vérifier le grain en comparant les lignes en entrée et en sortie d'une jointure.
- Relever les blocs `shared hit` et `read`, ainsi que les éventuels blocs `temp`. Un bloc `read` a dû être chargé dans les tampons PostgreSQL, éventuellement depuis le cache du système. Les compteurs d'un nœud incluent les enfants.
- Garder mêmes données, requête, paramètres et méthode avant/après. Isoler le premier passage puis prendre la médiane d'au moins trois répétitions. Conserver les plans complets. Mesurer le coût de construction et la taille de l'index à part. Un index existant peut être ignoré par le planificateur.

Sources. [Lire EXPLAIN dans PostgreSQL](https://www.postgresql.org/docs/17/using-explain.html) · [Options EXPLAIN](https://www.postgresql.org/docs/17/sql-explain.html)

## Missions et traces à conserver

| Mission | Trace technique |
| --- | --- |
| M1 · Benchmark | Requêtes du groupe, preuve du volume, référence sans index, plans et conditions de mesure. |
| M2 · Optimisation | Définition de l'index choisi, plans et répétitions après création, comparaison sur des filtres de fréquences différentes. |
| M3 · Analyse critique | Interprétation de la dégradation A10, de la faible sélectivité, de la multiplication des lignes et des écarts estimés/réels. Distinguer un problème de plan ou de grain d'une erreur dans les données. Documenter les limites du cache et du poste. |
| M4 · Jalon collectif | Rassembler schéma, imports, requêtes et indicateurs S1, analyses S2, puis benchmark, plans et justification S3. Déposer le tout selon les consignes du formateur. |

L'exemple indépendant sur des capteurs montre un changement de plan dans une transaction annulée :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s3/exemple.sql
```

Pour conserver un plan obtenu depuis un fichier de requête du groupe, rediriger la sortie de `psql` vers votre dossier de travail. `\timing on` donne les temps affichés par le client. Pour étendre l'essai aux fenêtres et à la récursivité sur le grand volume, commencer par préciser le grain et le périmètre, prévoir une condition d'arrêt et limiter la sortie à des agrégats de contrôle plutôt qu'à des millions de lignes.

## Dépannage et reprise

- Port ou moteur indisponible. Vérifier `docker compose ps` et `docker compose logs --tail=50 postgres`. Examiner si une autre pile occupe 15432.
- Génération interrompue ou stockage insuffisant. Consulter les logs, vérifier l'espace du volume Docker et demander au formateur l'accès à la table de secours. La transaction de génération annule les créations si elle n'arrive pas à `COMMIT`.
- Schéma `benchmark` déjà présent. Vérifier la base courante et le nombre de lignes. Réutiliser le jeu s'il est complet et confirmer l'état des index avant la référence. En cas de doute, demander une base de benchmark distincte au formateur.
- Le secours fournit le même jeu sans index sur la table principale. Accéder à la copie préchargée ou faire restaurer le schéma dans une base ayant assez d'espace. En cas de machine lente, utiliser l'instance de secours prévue par le formateur. Conserver les travaux S1–S2 sur leur volume.

[Référence SQL cumulative](../REFERENCE_SQL.md)
