# NovaMarket S4 · dbt Core

## Vérifier l'intégration dbt

Le Compose cumulatif livré contient déjà le service `dbt`. Depuis `novamarket/`, vérifier sa présence :

```bash
docker compose --profile transfo config --services
```

Si `dbt` apparaît, passer à la préparation de l'environnement. Si vous utilisez encore un fichier Compose S1–S3 qui ne contient que PostgreSQL, copier d'abord `s4/` dans `novamarket/`, puis ajouter une seule fois ce bloc sous `services:` au même niveau que `postgres:` :

```yaml
  dbt:
    profiles: [transfo]
    build: ./s4
    working_dir: /work
    environment:
      HOME: /tmp
      DBT_SEND_ANONYMOUS_USAGE_STATS: "false"
    volumes:
      - ./s4/travail:/work
      - ./s4/exemple:/exemple:ro
    mem_limit: 1g
    cpus: 2
```

Garder le nom du projet, le service PostgreSQL, le réseau et le volume existants. Les services partagent le réseau Compose. Vérifier le YAML avec `docker compose --profile transfo config -q`, puis continuer avec les commandes suivantes.

## Préparer l'environnement

Reprendre le volume Docker et la base de S1–S3. Le service `dbt` est lancé à la demande avec Python 3.12, dbt Core 1.11.17, l'adaptateur PostgreSQL 1.10.2 et Git. Le premier build nécessite d'accéder au registre Docker, aux dépôts Debian et à PyPI. Préparer l'image avant la séance.

Depuis `novamarket/`, dans Bash, zsh ou WSL2 :

```bash
docker compose up -d --wait postgres
docker compose --profile transfo build dbt
mkdir -p s4/travail
docker compose run --rm --no-deps --user "$(id -u):$(id -g)" dbt bash
```

Le dernier appel ouvre un terminal dans le conteneur. `/work` est monté depuis `novamarket/s4/travail/`. Les fichiers créés ici restent accessibles à VS Code sur l'hôte après la fermeture du conteneur. Le dossier est ignoré par Git, car le profil local peut contenir un mot de passe. Si le projet est versionné ailleurs, exclure ce profil et les répertoires générés `target/` et `logs/`.

## M1 · Initialiser et connecter le projet

Dans le terminal du conteneur :

```bash
cd /work
dbt --version
mkdir -p /work/profil
dbt init novamarket_dbt --profiles-dir /work/profil
```

Renseigner les invites :

| Champ | Valeur locale |
| --- | --- |
| Adaptateur | PostgreSQL, choix `1` |
| Hôte | `postgres`, nom du service sur le réseau Compose |
| Port | `5432` |
| Utilisateur | `atelier` |
| Mot de passe | `novamarket_s1_local` avec les identifiants de démonstration |
| Base | `novamarket` ou la base de reprise indiquée par le formateur |
| Schéma de sortie | `s4_dbt`, ou un schéma dédié attribué au groupe |
| Threads | `2` |

```bash
cd /work/novamarket_dbt
dbt debug --profiles-dir /work/profil
```

Le port hôte `15432` sert aux clients exécutés hors de Docker. Depuis dbt, utiliser `postgres:5432`. Le nom `profile:` de `dbt_project.yml` doit correspondre à la clé en tête de `profiles.yml`. Les deux fichiers ont des fonctions différentes. `dbt_project.yml` décrit le projet et ses répertoires. `profiles.yml` décrit la connexion et la cible. [Commande dbt init](https://docs.getdbt.com/reference/commands/init)

## Exemple indépendant

Dans un second terminal **sur l'hôte**, depuis `novamarket/`, charger les trois relevés fictifs. Remplacer le nom de base si le profil pointe vers une autre base :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s4/exemple/preparer.sql
```

Le script crée le schéma `s4_exemple`. Si l'exemple a déjà été chargé, utiliser le schéma existant. Dans le terminal **dbt** :

```bash
cp -R /exemple/projet /work/exemple_cuves
cd /work/exemple_cuves
dbt compile --profiles-dir /work/profil
dbt run --profiles-dir /work/profil
dbt ls --profiles-dir /work/profil --select +mart_volumes --output name
```

Lire l'exemple dans [son dossier de modèles](exemple/projet/models). La source décrit une table externe. `source()` résout son nom et déclare sa dépendance. `ref()` lie deux modèles dbt et ordonne leur exécution. `config()` règle ici leur matérialisation. [source()](https://docs.getdbt.com/reference/dbt-jinja-functions/source) · [ref()](https://docs.getdbt.com/reference/dbt-jinja-functions/ref) · [Matérialisations](https://docs.getdbt.com/docs/build/materializations)

| Couche | Rôle | Matérialisations à comparer |
| --- | --- | --- |
| Staging | Décrire les sources, harmoniser colonnes et types, expliciter le grain et la qualité. | Une `view` restitue le SQL à la lecture et garde une relation inspectable. |
| Intermediate | Construire des transformations réutilisables et maîtriser les cardinalités. | Un modèle `ephemeral` est intégré comme CTE à ses consommateurs. Pour inspecter ou réutiliser physiquement une sortie, choisir une vue ou une table selon le besoin. |
| Marts | Publier un résultat analytique au grain défini. | Une `table` stocke le résultat et le reconstruit à l'exécution du modèle. |

## M2 à M5 · Construire et vérifier

Les tables transactionnelles validées en S1–S2 restent vos sources. Le benchmark S3 est dans son schéma dédié. Pour étudier les anomalies, charger les variantes dans la réception séparée de S4. Depuis `novamarket/` **sur l'hôte** :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s4/preparer_reception.sql
```

Le script vise le schéma canonique `public` et les identifiants S1 de référence. Si le groupe a changé le schéma ou les noms de colonnes, adapter le chemin de lecture ou demander la base de reprise. Réutiliser la réception si elle existe déjà. La colonne `quantity_text` conserve la valeur brute. Les cas à examiner couvrent valeurs manquantes, écritures incompatibles avec le type attendu, doublons et références absentes. Les paiements multiples du jeu transactionnel permettent d'examiner la multiplication lors d'une jointure.

- **M2 — Sources et staging.** Déclarer les sources PostgreSQL en YAML, créer vos modèles staging et rendre visibles les anomalies de réception. Garder les sources importées comme point de comparaison.
- **M3 — Transformations.** Expliciter le grain de chaque entrée, les règles commerciales et l'effet des jointures. Choisir les transformations intermédiaires.
- **M4 — Marts.** Définir le grain et les mesures des sorties analytiques, ainsi que la matérialisation qui convient.
- **M5 — Exécution.** Compiler, exécuter et examiner le graphe. Vérifier volumes, clés et totaux par rapport à S1–S2. Rejouer la chaîne et comparer les résultats.

Dans le conteneur, revenir au projet du groupe :

```bash
cd /work/novamarket_dbt
dbt compile --profiles-dir /work/profil
dbt run --profiles-dir /work/profil
dbt ls --profiles-dir /work/profil --output name
```

Le projet généré par dbt contient ses propres modèles de démonstration. Pour isoler l'exécution de vos modèles, déplacer ce dossier d'exemple hors de `models/` une fois sa lecture terminée, ou cibler vos modèles avec `--select`. Le SQL compilé est dans `target/compiled/` et `target/manifest.json` expose les dépendances. Contrôler dans `psql` avec `\dt s4_dbt.*` et `\dv s4_dbt.*`, en adaptant le nom du schéma.

## Dépannage

| Symptôme | Action |
| --- | --- |
| Image introuvable | Relancer le build Compose avec le profil `transfo`. Si un téléchargement échoue, utiliser l'image préparée par le formateur. |
| Connexion refusée | Vérifier `docker compose ps`, puis `postgres:5432`, la base et les identifiants dans le profil. |
| Profil introuvable | Confirmer le chemin `/work/profil` et l'égalité du nom de profil et de la clé YAML. |
| Source non trouvée à l'exécution | Vérifier dans `psql` la base, le schéma et la relation, puis la déclaration YAML. |
| Un intermédiaire manque dans `\dt` | Vérifier sa matérialisation. Un modèle `ephemeral` est intégré au SQL compilé du modèle dépendant. |
| Configuration ou projet bloqué | Conserver le dossier de travail et demander au formateur le projet de secours. |

`REFERENCE_SQL.md` : bibliothèque cumulative distribuée séparément par le formateur.
