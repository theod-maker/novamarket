# Démarrer NovaMarket S1

## Prérequis

- Ubuntu : Docker Engine et le plugin Compose.
- Windows : Docker Desktop avec le moteur WSL2, l'intégration de la distribution et les conteneurs Linux. Ouvrir le terminal WSL2 dans le répertoire du projet, sur le système de fichiers Linux.
- macOS : Docker Desktop adapté à Intel ou Apple Silicon. Exécuter les commandes dans le terminal.
- Vérifier `docker version` et `docker compose version`. Préparer l'image avant le cours avec `docker compose pull postgres`, depuis `novamarket/`. Le client SQL `psql` est fourni dans le conteneur.

## Démarrer et se connecter

Depuis `novamarket/` :

```bash
docker compose config -q
docker compose up -d --wait postgres
docker compose ps
docker compose exec postgres psql -X -U atelier -d novamarket
```

Dans `psql` :

```sql
SELECT current_database(), current_user;
SHOW server_version;
\dt
\q
```

Sur un volume neuf, `\dt` ne trouve aucune table. Pour un éditeur SQL sur l'hôte, utiliser `127.0.0.1:15432`, base `novamarket`, utilisateur `atelier` et mot de passe `novamarket_s1_local`. Ces identifiants servent à l'atelier local. Dans le conteneur, PostgreSQL utilise 5432. Pour les imports, employer `psql` dans Docker et les chemins `/s1/donnees/…`. Le répertoire de sources est monté en lecture seule.

## Essayer l'import sur un autre domaine

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f /s1/exemple/import.sql
```

L'exemple des ateliers culturels crée deux tables temporaires, charge le CSV et le NDJSON, vérifie une agrégation puis annule la transaction. Le fichier `exemple/planning_a_normaliser.csv` illustre une salle dont le nom et le responsable sont répétés à chaque réservation. Examiner les conséquences d'un changement de responsable, de l'ajout d'une salle avant sa première réservation et de la suppression de sa dernière réservation.

## Vérifier et dépanner

| Symptôme | Vérification et action |
| --- | --- |
| Le moteur ne répond pas | Lancer Docker Desktop ou vérifier le service Docker sous Ubuntu. Refaire `docker version` dans le terminal utilisé. |
| Le service tarde à démarrer | Lire `docker compose ps` et `docker compose logs --tail=50 postgres`. Vérifier l'accès à l'image et les ressources de Docker. |
| Le port 15432 est déjà occupé | Examiner `docker ps` et les programmes locaux. Si le pilote précédent est en cours, l'arrêter depuis son propre dossier. Préserver le PostgreSQL local sur 5432. |
| Le réseau chevauche une autre plage | Examiner `docker network ls`, les sous-réseaux Docker et les routes locales/VPN. Depuis le shell, définir `export NOVAMARKET_SUBNET='10.244.173.0/24'` uniquement si cette plage est libre. Si le réseau du kit existe déjà, `docker compose down` permet de le recréer avec la nouvelle plage en conservant le volume nommé. |
| Un fichier est introuvable | Vérifier le montage avec `docker compose exec postgres ls /s1/donnees`. Employer le chemin du conteneur pour `\copy` lorsque `psql` tourne dans Docker. |
| PostgreSQL signale une erreur de clé ou de type | Lire le numéro de ligne et le détail, vérifier en-tête et types, importer en réception et contrôler avant intégration. Après échec dans une transaction ouverte, exécuter `ROLLBACK;`. |

`docker compose stop` arrête le service en conservant les données. `docker compose up -d --wait postgres` reprend le travail sur le volume existant. En cas de blocage sur le chargement, prévenir le formateur pour basculer vers son état de référence.

Voir le [dictionnaire des sources](SOURCES.md), la [référence SQL](../../ressources/REFERENCE_SQL.md) et le [guide de sauvegarde et de reprise](../../ressources/SAUVEGARDE_SQL.md). Ce dernier décrit aussi les paramètres d’isolation lorsque plusieurs groupes partagent un hôte.
