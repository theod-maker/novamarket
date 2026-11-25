# S4 · Chargement PostgreSQL et dbt

Activer le venv S3. Garder le catalogue du groupe. Définir la connexion PostgreSQL locale via `NOVAMARKET_DSN` dans le shell ou un fichier privé. Exemple de format sans secret : `host=127.0.0.1 port=15432 dbname=novamarket user=atelier`. Utiliser `PGPASSFILE` ou ajouter le mot de passe local dans la variable du shell. Le client échoue si aucune connexion n'est définie. Exécuter `python transformation/exemple.py` pour vérifier le comportement transactionnel sur des cuves temporaires.

Développer `transformation/chargement_postgres.py`. Lire le JSONL valide, convertir les types, contrôler les références produit, les unités et les dates. Choisir un schéma fournisseur séparé et une clé compatible avec plusieurs dates par offre. Utiliser une transaction, tracer les lignes insérées, réutilisées et rejetées, puis vérifier le résultat en rejouant le lot. Un échec en transaction ne doit laisser aucune écriture partielle. L'entrée de secours [offres.jsonl](secours/offres.jsonl) est un jeu de 20 offres valides issu de la simulation `atelier`. Les rejets sont exclus de ce fichier.

## Un seul projet dbt

Le projet courant est `transformation/dbt/`, monté sur `/projet`. Si le groupe possède déjà un projet dbt, sauvegarder l'ancien dossier puis intégrer **ses propres** modèles et tests dans cette arborescence, en conservant un seul `dbt_project.yml` de travail. `s4/travail/` reste disponible pour le profil et les fichiers historiques. Le Compose cumulatif contient le service dbt. Construire l'image une fois avec `docker compose --profile transfo build dbt`.

Créer ou réutiliser `s4/travail/profil/profiles.yml`. Le modèle `transformation/dbt/profiles.exemple.yml` donne les paramètres sans secret. Saisir le mot de passe local dans une variable de session, sans l'inscrire dans les commandes partagées :

```bash
read -rs DBT_ENV_SECRET_PASSWORD
export DBT_ENV_SECRET_PASSWORD
export DBT_DATABASE=novamarket
docker compose run --rm --no-deps --user "$(id -u):$(id -g)" -w /projet \
  -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt bash
```

Dans le conteneur, lancer `dbt debug --profiles-dir /work/profil`, puis les commandes `compile`, `run` et `build` avec le même chemin. Le DNS Docker est `postgres:5432`. Voir les explications et [l'exemple dbt sur des cuves](../s4/README.md#exemple-indépendant). Déclarer les relations PostgreSQL en YAML avec `source()`, poser le grain des modèles staging, assembler les étapes avec `ref()`, et comparer vues, tables et modèles éphémères. Inspecter le SQL compilé et les dépendances avant de publier un premier mart.

## Vérification S5 en fin de S4

Installer le verrou volumétrie en amont. Lancer les vérifications Python, Java, HF public et Spark du [guide S5](../volumetrie/README.md). Sur le Hub, utiliser son propre compte, vérifier l'authentification et le droit de créer un dépôt de dataset privé. Ne jamais envoyer de token au formateur. En cas d'échec d'authentification, garder les sorties locales et demander un créneau ou un compte autorisé. La publication devra être exécutée lorsque l'accès est disponible.
