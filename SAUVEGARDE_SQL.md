# Sauvegarde et reprise des travaux NovaMarket

## Garder la même pile au fil des séances

Réutiliser le même dossier `novamarket/`, le même nom de projet Compose et le même volume. Une pile locale par groupe suffit. Le compte PostgreSQL `atelier` est administrateur de son instance pédagogique. Chaque groupe doit conserver sa propre instance lorsqu'un hôte est partagé.

Les valeurs par défaut sont le projet `novamarket-s1`, les ports hôtes PostgreSQL `15432` et Metabase `13000`, et le sous-réseau `10.244.172.0/24`. Pour créer une **nouvelle pile indépendante** sur un hôte qui héberge déjà d'autres groupes, attribuer un nom, deux ports et un sous-réseau libres. L'exemple suppose des valeurs vérifiées par le formateur :

```bash
export COMPOSE_PROJECT_NAME=novamarket-groupe02
export NOVAMARKET_PG_PORT=25432
export NOVAMARKET_MB_PORT=23000
export NOVAMARKET_SUBNET=10.244.174.0/24
docker compose --profile transfo --profile bi config -q
docker compose up -d --wait postgres
```

Réutiliser ces valeurs à chaque ouverture de terminal sur cette pile. Les ports internes et le nom d'hôte dbt et Metabase restent `postgres:5432`. Si le port hôte du serveur de documentation dbt est pris, choisir séparément son mappage. Changer le nom de projet d'une pile existante crée un autre volume. Retrouver le nom initial pour réutiliser les données.

## Créer un point de reprise

Faire une sauvegarde après une étape validée, en particulier après S2, après les travaux dbt et après le second snapshot de S5. Arrêter les imports et les commandes dbt pendant la prise des fichiers et de la base pour conserver le même état. Depuis `novamarket/`, choisir la base à sauvegarder :

```bash
base=novamarket
umask 077
mkdir -p "$HOME/sauvegardes-novamarket"
backup=$(mktemp -d "$HOME/sauvegardes-novamarket/groupe.XXXXXX")
docker compose exec -T postgres pg_dump -U atelier -Fc --no-owner --no-acl "$base" > "$backup/base.dump"
docker compose exec -T postgres pg_restore -l < "$backup/base.dump" > "$backup/inventaire.txt"
printf '%s\n' "$backup"
```

Vérifier que les deux commandes réussissent. L'archive de base inclut les schémas du groupe présents, y compris le benchmark s'il est chargé. À la fin de S5, repérer dans l'inventaire le snapshot client, sa source courante et le mart mensuel S5. Le snapshot capture les états déjà observés. Conserver l'archive et une copie hors du poste de travail.

À partir de S4, sauvegarder aussi le dossier de projet dbt, en adaptant son nom :

```bash
tar --exclude=target --exclude=logs --exclude=dbt_packages \
    --exclude=profiles.yml --exclude='.env*' \
    -C s4/travail -czf "$backup/projet-dbt.tar.gz" novamarket_dbt
tar -tzf "$backup/projet-dbt.tar.gz"
```

Conserver les requêtes S1–S3, les scripts d'import et les notes du groupe. Relever le nom du profil, la base, les schémas de sortie et les versions. Garder le profil et les identifiants séparément avec accès restreint. Vérifier l'archive avant de la partager si le groupe a ajouté d'autres fichiers de configuration.

En S6, sauvegarder séparément les métadonnées Metabase sur l'instance qui héberge votre dashboard :

```bash
docker compose exec -T postgres pg_dump -U atelier -Fc --no-owner --no-acl \
  "${NOVAMARKET_MB_APP_DB:-metabase_s6_app}" > "$backup/metabase-app.dump"
```

Cette archive contient des comptes et des connexions. La garder hors des rendus ordinaires. L'archive PostgreSQL analytique reste nécessaire. Un tableau de bord restauré doit pointer vers la bonne base analytique.

## Restaurer dans une base neuve

Toujours choisir un nom libre. Lancer ces commandes sur la pile de destination avec PostgreSQL en état sain :

```bash
base_reprise=novamarket_reprise_groupe
docker compose exec -T postgres createdb -U atelier "$base_reprise" &&
docker compose exec -T postgres pg_restore -U atelier --single-transaction \
  --exit-on-error --no-owner --no-acl -d "$base_reprise" < "$backup/base.dump"
```

Vérifier les schémas et les comptages avec `psql`. Adapter le profil dbt à la base restaurée, lancer `dbt debug`, puis vérifier les résultats de la dernière étape. Avant S6, contrôler le snapshot avec ses versions courantes et closes, ainsi que le mart mensuel S5. Pour rendre la publication de nouveau lisible dans Metabase, préparer le rôle BI et réappliquer les droits sur le schéma publié. Le formateur restaure, si nécessaire, les métadonnées de Metabase dans une base applicative séparée.

Si la sauvegarde du groupe est indisponible, demander l'état canonique au formateur et reprendre dans une base distincte. Les états fournis permettent de poursuivre les exercices. Les travaux propres au groupe et l'historique déjà capturé sont préservés par ses sauvegardes.
