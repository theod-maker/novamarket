# S3 M2 à M4 : Collecteur asynchrone des offres

## Fonctionnement

```
API /offers ──aiohttp──► collecteur.py ──► data/raw/<run>.jsonl        (réponses reçues)
                              │
                         validation.py
                      ┌───────┴────────┐
                 offre OK         offre fausse
                      ▼                 ▼
     data/valid/offres.jsonl   data/rejected/<run>.jsonl (page, position, motif, offre)

journalisation.py ──► data/logs/<run>.log et data/bilans/<run>.json
```

| Fichier | Rôle |
| --- | --- |
| `ingestion/src/collecteur.py` | pagination, concurrence limitée, reprises après erreur |
| `ingestion/src/validation.py` | règles de contrôle et motif de rejet de chaque offre |
| `ingestion/src/journalisation.py` | journal, fichiers JSONL, bilan |
| `ingestion/tests/test_validation.py` | tests des règles, sans appel à l'API |
| `scripts/run_ingestion.sh` | rejoue les 4 essais |

## M2 : Collecte concurrente limitée

- Une seule `aiohttp.ClientSession` pour tous les appels, avec un timeout de 1 s par requête.
- La page 1 est lue d'abord pour connaître `total_pages`. Les pages 2 à 6 sont ensuite lancées
  ensemble avec `asyncio.gather`.
- `asyncio.Semaphore(3)` limite à 3 le nombre d'appels HTTP en même temps.
- `--concurrence 1` donne une collecte séquentielle, pour comparer.

| Essai (`clean`) | Requêtes HTTP | Durée |
| --- | --- | --- |
| séquentiel (`--concurrence 1`) | 6 | 0,76 s |
| concurrent (`--concurrence 3`) | 6 | 0,38 s |

Le gain est de 2 et non de 6 : la page 1 passe seule, puis les 5 autres pages passent en 2 vagues
de 3 au plus, soit 3 allers-retours au lieu de 6.

## M3 : Erreurs et reprises

| Cas | Réaction |
| --- | --- |
| 429 (trop de requêtes) | attendre `Retry-After` secondes, puis réessayer |
| 5xx (serveur indisponible) | attendre 0,2 s, puis 0,4 s, puis 0,8 s, et réessayer |
| timeout (plus de 1 s) ou erreur de connexion | même attente, puis réessayer |
| 200 avec un JSON invalide | même attente, puis réessayer |
| autre erreur 4xx (400, 404...) | arrêt immédiat, réessayer ne changerait rien |

- 4 tentatives au plus par page, chacune écrite dans le journal.
- Si une page échoue 4 fois, la collecte s'arrête et aucun fichier valide n'est écrit : on ne publie
  pas un lot incomplet.

Essai `atelier` : 9 requêtes pour 6 pages, soit 3 reprises (429 sur la page 2, JSON invalide sur la
page 3, timeout sur la page 4), en 1,45 s.

Essai `panne` : la page 6 répond 503 quatre fois. Le bilan indique `"statut": "echec"`, le programme
se termine avec le code 1, et `valid/offres.jsonl` n'est pas modifié.

## M4 : Validation et rejets

Une offre est rejetée au premier problème trouvé :

1. `champ manquant` : un des 7 champs du contrat est absent ;
2. `prix invalide` : `price_cents` n'est pas un entier positif ou nul ;
3. `unites invalides` : `available_units` n'est pas un entier positif ou nul ;
4. `devise invalide` : autre que `EUR` ;
5. `date invalide` : `observed_on` n'est pas une date ISO ;
6. `produit inexistant` : `product_id` absent du catalogue S2 (`s2/donnees/products.csv`) ;
7. `doublon` : `offer_id` déjà accepté plus tôt dans le lot (la première offre est gardée).

| Essai | Lignes vues | Valides | Rejetées | Motifs |
| --- | --- | --- | --- | --- |
| `clean` | 24 | 24 | 0 | |
| `atelier` | 24 | 20 | 4 | `O005` champ manquant, `O010` prix invalide, `O017` produit inexistant, `O001` doublon (page 6) |

Le résultat `atelier` correspond au contrôle du livret (24 offres, 20 valides, 4 rejets).

## Rejouer

```bash
./scripts/run_ingestion.sh
```

Le script redémarre l'API, ce qui remet à zéro son compteur de tentatives : les incidents de
`atelier` se reproduisent alors à chaque exécution, avec les mêmes compteurs. Les fichiers d'un même
`run` sont réécrits, pas complétés.

## Limites

- Le catalogue de référence est lu dans `s2/donnees/products.csv`, pour que le collecteur
  fonctionne sans PostgreSQL. En S4, il pourra être lu dans `core.products`.
- Le 503 de `panne` est réessayé comme une erreur passagère : l'API ne permet pas de savoir qu'il est
  définitif.
- `valid/offres.jsonl` contient le dernier lot complet. Le script lance `atelier` en dernier : c'est
  ce lot qui sert en S4.
- Les durées sont mesurées sur un seul poste, avec la latence par défaut de l'API (0,12 s).
