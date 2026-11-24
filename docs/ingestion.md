# S3 M2 à M4 : Collecteur asynchrone des offres

## Fonctionnement

```
API /offers ──aiohttp──► collecteur.py ──► data/raw/<run>.jsonl        (chaque tentative reçue)
                              │
                         validation.py
                      ┌───────┴────────┐
                 offre OK         offre fausse
                      ▼                 ▼
     data/valid/offres.jsonl   data/rejected/<run>.jsonl (page, position, motif, offre brute)

journalisation.py ──► data/logs/<run>.log et data/bilans/<run>.json
```

| Fichier | Rôle |
| --- | --- |
| `ingestion/src/collecteur.py` | pagination, concurrence bornée, reprises, publication du lot |
| `ingestion/src/validation.py` | règles du contrat et motif de rejet de chaque offre |
| `ingestion/src/journalisation.py` | journal, écriture JSONL UTF-8, bilan |
| `ingestion/tests/test_validation.py` | 15 contrôles des règles, sans appel à l'API |
| `scripts/run_ingestion.sh` | rejoue les 4 essais de référence |

## M2 : Collecte concurrente bornée

- Une seule `aiohttp.ClientSession` pour tous les appels, avec un timeout de 1 s par requête.
- La page 1 est lue d'abord, pour connaître `total_pages`. Les pages 2 à 6 sont lancées ensemble avec
  `asyncio.gather`.
- Un `asyncio.Semaphore(concurrence)` limite le nombre d'appels HTTP en cours (3 par défaut).
  Le bilan donne `appels_simultanes_max`, mesuré pendant l'exécution : il ne dépasse jamais la limite.
- `--concurrence 1` donne la collecte séquentielle, avec le même code, pour comparer.

| Essai (`clean`, latence 0,12 s) | Appels simultanés max | Requêtes HTTP | Durée |
| --- | --- | --- | --- |
| séquentiel (`--concurrence 1`) | 1 | 6 | 0,76 s |
| concurrent (`--concurrence 3`) | 3 | 6 | 0,39 s |

Le gain est de 2 et non de 6 : la page 1 passe seule, puis les 5 autres pages passent en 2 vagues de
3 au plus, soit 3 allers-retours au lieu de 6.

## M3 : Erreurs et reprises

| Cas | Classement | Réaction |
| --- | --- | --- |
| 429 | transitoire | attente de `Retry-After` secondes (5 s au plus), puis nouvelle tentative |
| 500, 502, 503, 504 | transitoire | attente de 0,2 s, 0,4 s, puis 0,8 s, puis nouvelle tentative |
| timeout (plus de 1 s) ou erreur de connexion | transitoire | même attente |
| 200 avec JSON invalide ou structure non conforme | transitoire | même attente |
| autre code (400, 404...) | permanent | arrêt immédiat de la collecte |

- 4 tentatives au plus par page. Chaque tentative est écrite dans le journal et dans `raw/`.
- L'attente se fait hors du sémaphore : une page qui patiente ne bloque pas une place pour les autres.
- Si une page échoue définitivement, la collecte s'arrête et **aucun lot n'est publié**. Le fichier
  `valid/offres.jsonl` est d'abord écrit dans un fichier provisoire, puis renommé : il n'existe
  jamais à moitié écrit, et un échec laisse en place le dernier lot complet.

Essai `atelier` : 9 requêtes HTTP pour 6 pages, soit 3 reprises (429 sur la page 2, JSON invalide sur
la page 3, timeout sur la page 4), en 1,46 s.

Essai `panne` : la page 6 répond 503 quatre fois, le bilan indique `"statut": "echec"` avec 5 pages
sur 6, le programme se termine avec le code 1 et `valid/offres.jsonl` n'est pas modifié (vérifié par
empreinte du fichier avant et après).

## M4 : Validation et rejets

Une offre est rejetée au premier motif trouvé, dans cet ordre :

1. `offre non objet` ;
2. `champ manquant : <champs>` ;
3. `offer_id invalide`, `supplier_id invalide` : texte vide ou absent ;
4. `product_id non entier`, `prix invalide`, `unites invalides` : pas un entier, ou négatif ;
5. `devise inconnue` : autre que `EUR` ;
6. `date invalide` : pas au format `AAAA-MM-JJ`, ou date impossible ;
7. `produit inexistant` : `product_id` absent du catalogue S2 ;
8. `doublon` : `offer_id` déjà accepté plus tôt dans le lot (la première offre est gardée).

Une valeur booléenne n'est pas acceptée comme entier (en Python, `True` est un `int`).

| Essai | Lignes vues | Valides | Rejetées | Motifs |
| --- | --- | --- | --- | --- |
| `clean` | 24 | 24 | 0 | |
| `atelier` | 24 | 20 | 4 | `O005` champ manquant, `O010` prix invalide, `O017` produit inexistant, `O001` doublon (page 6) |

Le résultat `atelier` correspond au contrôle de complétude donné dans le livret (24 offres, 20
valides, 4 rejets). Chaque bilan vérifie `lignes_vues = valides + rejetees` (`controle_ok`).

## Rejouer

```bash
./scripts/run_ingestion.sh
```

Le script redémarre l'API pour remettre à zéro ses compteurs de tentatives : les incidents de
l'essai `atelier` se reproduisent alors à l'identique, et une relance donne les mêmes fichiers et les
mêmes compteurs. Le même `run` écrase ses propres fichiers au lieu de les dupliquer.

## Limites

- Le catalogue de référence est lu dans `s2/donnees/products.csv` (identifiants 1 à 24) pour que le
  collecteur fonctionne sans PostgreSQL. En S4, il pourra être lu dans `core.products`.
- Le 503 de `panne` est permanent, mais il est réessayé comme un incident transitoire : le livret
  le range parmi les erreurs transitoires, et l'API ne permet pas de distinguer les deux cas.
- `valid/offres.jsonl` contient le dernier lot complet, quel que soit le scénario : le script lance
  `atelier` en dernier, c'est donc ce lot qui sert en S4.
- Les durées sont mesurées sur un seul poste, avec la latence par défaut de l'API (0,12 s).
