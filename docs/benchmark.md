# S2 M3 : benchmark et index

Scripts : `s3/generer.sql` (fourni), `sql/benchmark/*.sql`, lancés par `./scripts/run_benchmark.sh`.
Plans complets : `resultats/benchmark/`. Le jeu `benchmark` est séparé des ventes NovaMarket.

## Contexte de mesure

`resultats/benchmark/0_contexte.txt` : PostgreSQL 17.12 dans Docker Desktop sur Mac Apple Silicon,
conteneur limité à 2 CPU et 2 Go, `shared_buffers = 128MB`, 2 workers parallèles maximum.

- Volume vérifié : `SELECT count(*) FROM benchmark.benchmark_sales` donne 10 000 000.
- Table : 498 Mo, soit environ 63 700 pages de 8 Ko. Elle ne tient pas dans `shared_buffers`
  (128 Mo) : chaque parcours complet relit environ 47 500 pages (`read`), probablement depuis le cache
  du système. Les temps restent donc stables entre passages, mais ce ne sont pas des lectures disque
  « à froid ».

## Protocole

1. Supprimer l'index s'il existe, puis `ANALYZE`.
2. Pour chaque requête : `EXPLAIN` (plan estimé), puis 4 fois `EXPLAIN (ANALYZE, BUFFERS)`. Le
   1er passage est isolé, et on retient la médiane des passages 2 à 4.
3. Créer l'index et mesurer sa durée de création et sa taille.
4. Refaire exactement les mêmes mesures.

Les deux requêtes renvoient le même résultat avant et après l'index (vérifié en tête des fichiers 1 et 3) :

```sql
SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42;  -- sélectif
SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;   -- large
```

Sélectivité (X1) : le magasin 42 a 100 ventes (0,001 %), le magasin 1 en a 9 500 000 (95 %).

## Index choisi

```sql
CREATE INDEX benchmark_sales_store_id_idx ON benchmark.benchmark_sales (store_id);
```

Il porte sur la colonne filtrée. Création : 1,27 s. Taille : 66 Mo, soit +13 % par rapport à la table.

## Mesures (ms, `Execution Time`)

| Requête | Sans index : médiane | Avec index : médiane | Plan sans index | Plan avec index |
| --- | --- | --- | --- | --- |
| sélective (`store_id = 42`) | 122,8 | 0,021 | Parallel Seq Scan, 63 700 pages | Index Scan, 103 pages |
| large (`store_id = 1`) | 392,4 | 397,7 | Parallel Seq Scan | Parallel Seq Scan (index ignoré) |
| large, index forcé (`enable_seqscan = off`) | | 470,1 | | Bitmap Heap Scan, 71 700 pages |

Les détails par passage sont dans `resultats/benchmark/resume_mesures.md`. Le 1er passage avec index
(0,057 ms) est plus lent que les suivants (0,02 ms) : les pages de l'index ne sont pas encore en mémoire.

## Interprétation

**Filtre sélectif : index efficace.** Sans index, PostgreSQL lit toute la table pour garder 100 lignes
(« Rows Removed by Filter: 3 333 300 » par worker). Avec l'index, il lit 103 pages au lieu d'environ
63 700. La requête passe de 123 ms à 0,02 ms, soit près de 6 000 fois plus vite.

**Filtre large : index inefficace.** Pour 95 % des lignes, le planificateur garde le parcours
séquentiel même quand l'index existe : il faudrait de toute façon lire presque toutes les pages.
Le temps ne change pas (392 contre 398 ms, l'écart reste dans la variation entre passages).

**Dégradation quand on force l'index.** Avec `enable_seqscan = off`, PostgreSQL utilise l'index
(Bitmap Heap Scan). Il lit alors l'index **et** la table, soit 71 700 pages contre 63 700, et la requête
devient 20 % plus lente (470 contre 392 ms). Un index présent n'est donc pas forcément un index utile.

**Coût de l'index.** 66 Mo de disque, 1,3 s de création, et chaque insertion dans la table devra
aussi mettre l'index à jour. Il est rentable pour les recherches sur des magasins peu actifs, inutile
pour le magasin 1.

## Multiplication des lignes (X3)

Le magasin 42 appartient à 2 campagnes. Joindre ses ventes à `campaign_assignments` donne 200 lignes
au lieu de 100, et la somme des montants passe de 10 100 € à 20 200 €. Le plan le montre :
`Index Scan` donne 100 lignes, le `Nested Loop` en sort 200. C'est un problème de grain (une vente
× une campagne), pas une erreur dans les données. Il faut compter les ventes avant de joindre, ou
présenter le résultat par campagne en précisant qu'une vente peut compter pour plusieurs campagnes.

## Écart entre lignes estimées et réelles (X4, X5)

Dans ce jeu, `zone_id` et `channel_id` sont toujours égaux (X4 : 10 000 000 lignes où
`zone_id = channel_id`). PostgreSQL suppose que deux colonnes sont indépendantes :

| Filtre | Lignes estimées | Lignes réelles |
| --- | --- | --- |
| `zone_id = 3 AND channel_id = 3` | environ 100 000 (10 % × 10 %) | 1 000 000 |
| `zone_id = 3 AND channel_id = 4` | environ 100 000 | 0 |

L'estimation est 10 fois trop basse dans le 1er cas, et elle annonce 100 000 lignes là où il n'y en a
aucune dans le 2e. Ici, le plan reste un parcours séquentiel, donc sans conséquence. Mais dans une
requête plus complexe, une mauvaise estimation peut faire choisir une mauvaise jointure.

Correction testée (X5, annulée par `ROLLBACK`) : `CREATE STATISTICS ... (dependencies) ON zone_id,
channel_id`, puis `ANALYZE`. L'estimation passe à environ 1 000 000 lignes, ce qui correspond à la réalité.

Autre écart observé : pour `store_id = 42`, l'estimation est de 373 lignes pour 100 réelles. Les
statistiques sont calculées sur un échantillon, et les 5 000 petits magasins sont trop nombreux pour
être tous connus précisément.

## Limites

- Mesures sur un seul poste, avec d'autres applications ouvertes. La variation entre passages est
  d'environ ±15 % (par exemple 121 à 160 ms sans index).
- Les données restent en partie en cache entre les essais. Le 1er passage n'est pas un vrai démarrage
  à froid (on n'a pas redémarré PostgreSQL ni vidé le cache du système).
- Le JIT et le parallélisme sont actifs, avec les réglages par défaut. Les résultats dépendent de ces
  réglages.
