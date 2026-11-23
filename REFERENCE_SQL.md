# Référence SQL NovaMarket

Référence cumulative S1–S6. Les exemples utilisent des réservations d'ateliers culturels, des capteurs et des cuves. Les commandes s'exécutent dans `psql`, dans le conteneur dbt ou dans l'éditeur natif de Metabase selon la section. [Exemple S1](s1/exemple/import.sql)

| Commande ou clause | Utilité | Syntaxe générale | Exemple |
| --- | --- | --- | --- |
| `CREATE TABLE` | Définir colonnes et types. `integer` pour un compte, `text` pour un libellé, `date` pour un jour, `jsonb` pour un objet. | `CREATE TABLE table_cible (colonne type, …);` | `CREATE TABLE salles (salle_id integer, nom text);` |
| `PRIMARY KEY`, `REFERENCES` | Identifier chaque ligne et contrôler les références. | `id integer PRIMARY KEY`, `parent_id integer REFERENCES parent(id)` | `salle_id integer REFERENCES salles(salle_id)` |
| `NOT NULL`, `CHECK` | Exiger une valeur et contrôler une règle locale. | `colonne type NOT NULL CHECK (condition)` | `heures integer NOT NULL CHECK (heures > 0)` |
| `CREATE TEMP TABLE` | Isoler une réception ou une démonstration dans la session en cours. | `CREATE TEMP TABLE nom (colonne type, …);` | `CREATE TEMP TABLE reception_json (document jsonb);` |
| `\copy` dans psql | Charger un fichier accessible au client. | `\copy table (colonnes) FROM 'chemin' WITH (FORMAT csv, HEADER true)` | `\copy salles (salle_id, nom) FROM '/s1/exemple/salles.csv' WITH (FORMAT csv, HEADER true)` |
| `INSERT INTO … SELECT` | Alimenter la cible après lecture et validation. | `INSERT INTO cible (colonnes) SELECT expressions FROM source;` | `INSERT INTO salles (salle_id, nom) SELECT salle_id, nom FROM reception_salles;` |
| `SELECT DISTINCT` | Retenir chaque combinaison de valeurs une seule fois après examen des doublons. | `SELECT DISTINCT colonnes FROM source;` | `SELECT DISTINCT salle_id, nom FROM reception_salles;` |
| `WHERE` | Filtrer les lignes avant agrégation. | `SELECT colonnes FROM table_source WHERE condition;` | `SELECT reservation_id FROM reservations WHERE heures >= 2;` |
| `INNER JOIN` | Garder les correspondances sur la condition de jointure. | `FROM a INNER JOIN b ON condition` | `FROM salles s INNER JOIN reservations r ON r.salle_id = s.salle_id` |
| `LEFT JOIN` | Conserver les lignes de gauche, même sans correspondance. | `FROM a LEFT JOIN b ON condition` | `FROM salles s LEFT JOIN reservations r ON r.salle_id = s.salle_id` |
| `CROSS JOIN` | Former toutes les paires entre deux ensembles. Vérifier les volumes avant de l'utiliser. | `FROM a CROSS JOIN b` | `FROM salles CROSS JOIN (VALUES ('matin'), ('soir')) AS c(creneau)` |
| `NOT EXISTS` | Tester l'absence d'une ligne correspondante. | `WHERE NOT EXISTS (SELECT 1 FROM b WHERE condition)` | `WHERE NOT EXISTS (SELECT 1 FROM reservations r WHERE r.salle_id = s.salle_id)` |
| `GROUP BY`, `HAVING` | Agréger par groupe et filtrer les groupes. | `SELECT cle, COUNT(*) FROM source GROUP BY cle HAVING COUNT(*) > n;` | `SELECT salle_id, COUNT(*) FROM reservations GROUP BY salle_id HAVING COUNT(*) > 1;` |
| `COUNT`, `SUM`, `AVG` | Compter et calculer total ou moyenne. `COUNT(*)` compte toutes les lignes, `COUNT(colonne)` ignore les valeurs nulles. | `SELECT COUNT(*), SUM(x), AVG(x) FROM source;` | `SELECT COUNT(*), SUM(heures), AVG(heures) FROM reservations;` |
| `COALESCE` | Donner une valeur de repli lorsqu'un résultat est nul. | `COALESCE(expression, valeur)` | `COALESCE(SUM(r.heures), 0)` |
| `BEGIN`, `COMMIT`, `ROLLBACK` | Regrouper des opérations et confirmer ou annuler le lot. | `BEGIN;` puis commandes, puis `COMMIT;` ou `ROLLBACK;` | `BEGIN; INSERT INTO salles VALUES (4, 'Gravure'); ROLLBACK;` |
| `\dt`, `\d` dans psql | Lister les tables ou inspecter types et contraintes. | `\dt` ou `\d nom` | `\d salles` |

## Importer du NDJSON avec psql

Chaque ligne doit contenir un objet JSON valide. Charger le document entier avec un séparateur et un caractère de citation de contrôle, absents des documents JSON du kit. Les quotes JSON ordinaires sont alors conservées. Déplier ensuite chaque objet avec des noms et types déclarés.

```sql
CREATE TEMP TABLE reception_json (document jsonb);
\copy reception_json FROM '/s1/exemple/reservations.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

SELECT r.reservation_id, r.salle_id, r.heures
FROM reception_json
CROSS JOIN LATERAL jsonb_to_record(document)
    AS r(reservation_id integer, salle_id integer, heures integer);
```

Les commandes commençant par `\` sont interprétées par `psql` et se terminent à la fin de la ligne.

## S2 · Fenêtres analytiques et CTE

| Commande ou clause | Utilité | Syntaxe générale | Exemple indépendant |
| --- | --- | --- | --- |
| `OVER`, `PARTITION BY` | Définir les lignes à comparer. La partition recommence le calcul à chaque groupe et conserve les lignes de détail. | `fonction() OVER (PARTITION BY groupe ORDER BY critere)` | `SUM(heures) OVER (PARTITION BY salle_id)` |
| `RANK` | Classer avec ex æquo et sauts dans la suite des rangs. | `RANK() OVER (PARTITION BY groupe ORDER BY valeur DESC)` | `RANK() OVER (PARTITION BY cuve ORDER BY volume DESC)` |
| `LAG`, `LEAD` | Lire la valeur précédente ou suivante dans l'ordre choisi. La valeur par défaut est `NULL` s'il n'y a pas de voisin. | `LAG(valeur) OVER (ORDER BY ordre)`, `LEAD(valeur) OVER (ORDER BY ordre)` | `LAG(volume) OVER (PARTITION BY cuve ORDER BY date_releve)` et `LEAD(volume) OVER (PARTITION BY cuve ORDER BY date_releve)` |
| `NTILE` | Répartir les lignes triées en groupes de tailles aussi proches que possible. | `NTILE(n) OVER (ORDER BY valeur DESC, cle)` | `NTILE(2) OVER (ORDER BY volume DESC, date_releve, cuve)` |
| `date_trunc`, `::date` | Ramener une date au début d'une période et afficher ce début comme une date. | `date_trunc('month', date_source)::date` | `date_trunc('month', date_releve)::date` |
| `WITH` | Nommer des étapes au sein d'une requête. | `WITH etape AS (SELECT …) SELECT … FROM etape;` | `WITH mesures AS (SELECT volume FROM releves) SELECT AVG(volume) FROM mesures;` |
| `WITH RECURSIVE`, `UNION ALL` | Démarrer sur une ancre et calculer les étapes suivantes à partir du résultat précédent, jusqu'à une condition d'arrêt. | `WITH RECURSIVE suite(n) AS (VALUES (0) UNION ALL SELECT n + 1 FROM suite WHERE n < 3) SELECT n FROM suite;` | Le scénario exécutable ajoute 5 degrés par palier jusqu'à 35. |

Le tri dans `OVER` détermine le calcul. Le `ORDER BY` final détermine l'affichage. Pour garder les ex æquo, le tri de `RANK` porte uniquement sur les critères de classement. Pour obtenir un ordre stable entre lignes de même valeur avec `NTILE`, ajouter une clé unique au tri. `LAG` et `LEAD` lisent les lignes voisines disponibles. S'il manque une période, elles accèdent directement à la prochaine ligne existante. Pour un parcours de données hiérarchiques, contrôler les cycles et prévoir une condition d'arrêt.

[Exemple S2 exécutable](s2/exemple.sql)

## S3 · Plans d'exécution et index

| Commande ou clause | Utilité | Syntaxe générale | Exemple indépendant |
| --- | --- | --- | --- |
| `EXPLAIN` | Afficher le plan estimé d'une requête. | `EXPLAIN SELECT …;` | `EXPLAIN SELECT avg(valeur) FROM releves WHERE capteur = 31;` |
| `EXPLAIN ANALYZE` | Exécuter la requête et ajouter les temps et lignes réellement observés. | `EXPLAIN ANALYZE SELECT …;` | `EXPLAIN ANALYZE SELECT avg(valeur) FROM releves WHERE capteur = 31;` |
| `BUFFERS` | Afficher les accès aux pages en plus du plan et des temps. | `EXPLAIN (ANALYZE, BUFFERS) SELECT …;` | `EXPLAIN (ANALYZE, BUFFERS) SELECT avg(valeur) FROM releves WHERE capteur = 31;` |
| `CREATE INDEX` | Créer un index. B-tree est la méthode par défaut, adaptée à de nombreuses recherches par égalité et intervalle. | `CREATE INDEX nom ON relation (colonne);` | `CREATE INDEX releves_capteur_idx ON releves (capteur);` |
| `DROP INDEX` | Supprimer un index de test identifié par son nom. | `DROP INDEX [IF EXISTS] [schema.]nom;` | `DROP INDEX releves_capteur_idx;` |
| `ANALYZE` | Actualiser les statistiques du planificateur après un chargement. | `ANALYZE relation;` | `ANALYZE releves;` |
| `pg_relation_size`, `pg_total_relation_size`, `pg_size_pretty` | Mesurer le stockage principal ou la taille totale avec index, puis rendre la mesure lisible. | `SELECT pg_size_pretty(pg_total_relation_size('schema.table'));` | `SELECT pg_size_pretty(pg_relation_size('releves_capteur_idx'));` |
| `\timing` dans psql | Afficher la durée vue par le client pour chaque commande SQL. | `\timing on` ou `\timing off` | Activer `\timing on` avant la requête sur les relevés. |

Les coûts estimés guident le choix du plan. Pour comparer des relevés, noter les temps d'exécution, les volumes, les buffers et le nombre de boucles. [Exemple S3 exécutable](s3/exemple.sql)

## S4 · dbt Core, YAML et Jinja

| Commande ou syntaxe | Utilité | Forme générale | Exemple indépendant |
| --- | --- | --- | --- |
| `dbt init` | Créer le projet et saisir le profil. | `dbt init nom_projet --profiles-dir dossier_profil` | `dbt init novamarket_dbt --profiles-dir /work/profil` |
| `dbt debug` | Vérifier le profil, le projet, Git et la connexion. | `dbt debug --profiles-dir dossier_profil` | `dbt debug --profiles-dir /work/profil` |
| `dbt compile` | Générer et inspecter le SQL rendu. | `dbt compile --profiles-dir dossier_profil` | Lire ensuite `target/compiled/atelier_cuves/models/mart_volumes.sql`. |
| `dbt run` | Construire les modèles sélectionnés dans l'ordre des dépendances. | `dbt run --select selection --profiles-dir dossier_profil` | `dbt run --select +mart_volumes --profiles-dir /work/profil` |
| `dbt ls` | Examiner les ressources d'une sélection. Le préfixe `+` inclut les parents. | `dbt ls --select +modele --output name` | `dbt ls --select +mart_volumes --output name --profiles-dir /work/profil` |
| `{{ source(...) }}` | Résoudre une table déclarée en YAML et enregistrer sa dépendance. | `{{ source('nom_source', 'nom_table') }}` | `FROM {{ source('capteurs', 'releves') }}` |
| `{{ ref(...) }}` | Référencer un modèle dbt et enregistrer sa dépendance. | `{{ ref('nom_modele') }}` | `FROM {{ ref('stg_releves') }}` |
| `{{ config(...) }}` | Configurer un modèle localement. On peut aussi fixer `+materialized` par dossier dans `dbt_project.yml`. | `{{ config(materialized='view') }}` ou remplacer `view` par `table` ou `ephemeral`. | `{{ config(materialized='view') }}` |
| `{{ env_var(...) }}` | Lire un paramètre d'environnement dans une configuration rendue par dbt. | `{{ env_var('VARIABLE') }}` | `password: "{{ env_var('DBT_PASSWORD') }}"` dans `profiles.yml`. |

```yaml
version: 2
sources:
  - name: capteurs
    schema: s4_exemple
    tables:
      - name: releves
```

Ce YAML donne le nom logique `capteurs.releves`. dbt résout la table physique à partir des propriétés de la source. Une vue, une table ou un SQL intégré en CTE correspondent respectivement à `view`, `table` et `ephemeral`. [Exemple S4 exécutable](s4/README.md#exemple-indépendant) · [Matérialisations dbt](https://docs.getdbt.com/docs/build/materializations)

## S5 · Tests, documentation et snapshots dbt

| Commande ou syntaxe | Utilité | Forme générale | Exemple indépendant |
| --- | --- | --- | --- |
| `data_tests` | Déclarer un test générique sur une relation ou colonne. | `data_tests: [not_null, unique]` | Vérifier que chaque `cuve_id` est renseigné et unique. |
| `accepted_values`, `relationships` | Vérifier un domaine ou une référence. Déclarer les paramètres sous `arguments`. | `accepted_values:` puis `arguments:` et `values:` en YAML. Pour `relationships`, utiliser `to` et `field`. | Pour une colonne niveau, `values: [haut, bas]`. |
| Test SQL singulier | Renvoyer uniquement les lignes qui violent une règle. Zéro ligne fait passer le test. | Fichier `tests/nom.sql` avec un `SELECT` des écarts. | `SELECT cuve_id FROM {{ ref('cuves') }} WHERE volume_litres < 0`. |
| `unit_tests`, `given`, `expect` | Vérifier la logique d'un modèle sur des fixtures minimales. | YAML sous `models/`, avec `model`, `given` et `expect`. | Fournir 39 et 40 litres, attendre respectivement `bas` et `haut`. |
| `dbt test` | Exécuter les tests sélectionnés. Les tests de données lisent les relations déjà construites. | `dbt test --select test_type:unit` ou `dbt test`. | Exécuter les contrôles du projet sur les cuves. |
| `dbt build` | Exécuter les ressources et les tests sélectionnés dans l'ordre du graphe. | `dbt build --exclude resource_type:snapshot`. | Reconstruire le modèle sur les cuves avant le premier passage du snapshot. |
| `description` | Décrire le grain, l'unité ou le sens d'un champ. | Clé YAML `description` sous la source, le modèle ou la colonne. | `description: Volume de la cuve en litres.` |
| `dbt docs generate`, `dbt docs serve` | Générer la documentation et démarrer son serveur local. | `dbt docs generate` puis `dbt docs serve --port 8080`. | Consulter le lineage de `atelier.cuves` et de son modèle consommateur. |
| `dbt snapshot` | Créer ou mettre à jour les versions SCD2 capturées. | `dbt snapshot --select nom_snapshot`. | `dbt snapshot --select historique_cuves` après avoir préparé l'état courant. |
| `dbt_valid_from`, `dbt_valid_to` | Inspecter les bornes de validité. Par défaut, la fin nulle signale une version courante. | `WHERE dbt_valid_to IS NULL` pour les versions courantes. | Vérifier quelles cuves sont courantes après le second passage. |

Exemple de déclaration dans un fichier YAML sous `snapshots/` :

```yaml
snapshots:
  - name: historique_cuves
    relation: source('atelier', 'cuves')
    config:
      unique_key: cuve_id
      strategy: timestamp
      updated_at: updated_at
```

Pour la stratégie `timestamp`, la source doit contenir une seule ligne par clé et faire progresser `updated_at` à chaque changement. Dans le kit, l'horodatage est de type PostgreSQL `timestamp`, en UTC par convention. Pour les tests unitaires, aligner les valeurs attendues sur les types réellement renvoyés, notamment l'échelle des nombres décimaux. [Exemple S5](s5/README.md#exemple-sur-des-cuves) · [Tests unitaires dbt](https://docs.getdbt.com/docs/build/unit-tests) · [Snapshots dbt](https://docs.getdbt.com/docs/build/snapshots)

## S6 · Publication et vérification des indicateurs BI

| Commande ou syntaxe | Utilité | Forme générale | Exemple indépendant |
| --- | --- | --- | --- |
| `GRANT USAGE ON SCHEMA` | Autoriser la résolution des noms dans un schéma publié. | `GRANT USAGE ON SCHEMA schema_bi TO lecteur;` | `GRANT USAGE ON SCHEMA s6_exemple TO metabase_s6_lecteur;` |
| `GRANT SELECT` | Autoriser la lecture des relations choisies. | `GRANT SELECT ON table_ou_vue TO lecteur;` | `GRANT SELECT ON s6_exemple.releves TO metabase_s6_lecteur;` |
| `grants` dans dbt | Réappliquer les droits lors de la construction d'un modèle. | `{{ config(grants={'select': ['role_lecteur']}) }}` | Rendre le modèle de relevés lisible par `metabase_s6_lecteur`. |
| `COUNT(DISTINCT …)` | Compter des identifiants distincts au périmètre retenu. | `COUNT(DISTINCT cle)` | Compter les cuves distinctes sur une période. |
| `GROUP BY ROLLUP` | Associer un total général aux agrégats par groupe. | `GROUP BY ROLLUP(jour)` | `SELECT jour, SUM(volume_litres) FROM s6_exemple.releves GROUP BY ROLLUP(jour);` |
| `IS DISTINCT FROM` | Comparer deux valeurs en tenant compte des valeurs nulles. | `a IS DISTINCT FROM b` | Comparer un total de cuve calculé et le total publié. |
| Prédicat temporel sur un intervalle | Rattacher un événement à une version en incluant le début et en excluant la fin. | `instant >= debut AND (instant < fin OR fin IS NULL)` | Rapprocher une mesure d'une période de calibration. |
| `[[AND {{periode}}]]` dans Metabase | Ajouter un filtre de champ optionnel à une question SQL native. | `WHERE true [[AND {{periode}}]]` | Associer `periode` à la colonne `jour` des relevés. |

Comparer les métriques à périmètre et grain identiques. Contrôler l'arrondi sur la valeur affichée et conserver les montants bruts dans les sorties de rapprochement. [Exemple S6](s6/README.md#démonstration-indépendante) · [Filtres Metabase](https://www.metabase.com/docs/latest/questions/native-editor/field-filters)
