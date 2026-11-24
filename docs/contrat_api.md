# S3 M1 : Contrat de l'API fournisseur

API locale lancée par `docker compose up -d --wait fournisseur`, adresse `http://127.0.0.1:18080`
(port modifiable avec `NOVAMARKET_API_PORT`). Elle fonctionne sans PostgreSQL.

## Endpoints

| Requête | Réponse |
| --- | --- |
| `GET /health` | `{"status": "ok"}` |
| `GET /offers?page=N&scenario=S&run=R` | une page d'offres |
| page hors de 1..6, scénario inconnu, `run` invalide | `400 {"error": "parametres"}` |

`scenario` vaut `clean`, `atelier` ou `panne`. `run` (lettres, chiffres, `-`, `_`, 64 caractères
au plus) identifie un essai : l'API compte les tentatives par (scénario, run, page), et les incidents
du scénario `atelier` n'arrivent qu'à la première tentative. Il faut donc un `run` neuf, ou
redémarrer le service, pour les rejouer.

## Pagination et condition d'arrêt

Pagination par numéro : 6 pages de 4 offres, soit 24 offres. Chaque page contient `page`,
`total_pages`, `next_page` et `items`. `next_page` vaut `null` sur la dernière page.

Le collecteur lit la page 1, prend `total_pages` (6), demande les pages 2 à 6 en concurrence, puis
vérifie que la dernière page a bien `next_page = null`. Une page dont le numéro ne correspond pas à
celui demandé, ou sans liste `items`, est traitée comme une réponse non conforme.

## Une offre

Grain : une offre d'un fournisseur pour un produit, à une date d'observation.
Clé métier : `offer_id`.

| Champ | Type | Règle |
| --- | --- | --- |
| `offer_id` | texte | non vide, unique dans le lot (`O001` à `O024`) |
| `supplier_id` | texte | non vide (`F01`, `F02`, `F03`) |
| `product_id` | entier | existe dans le catalogue S2 (`s2/donnees/products.csv`) |
| `price_cents` | entier | prix en centimes, `>= 0` |
| `currency` | texte | `EUR` |
| `available_units` | entier | unités disponibles, `>= 0` |
| `observed_on` | texte | date ISO `AAAA-MM-JJ` |

Exemple de réponse (page 1, scénario `clean`, données fictives de la simulation, coupée à une offre) :

```json
{
  "page": 1,
  "total_pages": 6,
  "next_page": 2,
  "items": [
    {"offer_id": "O001", "supplier_id": "F01", "product_id": 1, "price_cents": 625,
     "currency": "EUR", "available_units": 2, "observed_on": "2026-11-24"}
  ]
}
```

## Comparaison des scénarios (observée avec `curl`)

| Page | `clean` | `atelier`, 1re tentative | `atelier`, offres reçues | `panne` |
| --- | --- | --- | --- | --- |
| 1 | 200 | 200 | correctes | 200 |
| 2 | 200 | **429**, `Retry-After: 1` | `O005` sans `supplier_id` | 200 |
| 3 | 200 | **200 mais corps `{json-incomplet`** | `O010` avec `price_cents = "inconnu"` | 200 |
| 4 | 200 | 200 après environ 1,5 s (délai) | correctes | 200 |
| 5 | 200 | 200 | `O017` avec `product_id = 9999` | 200 |
| 6 | 200 | 200 | 4e offre = copie exacte de `O001` | **503 à chaque tentative** |

Un code 200 ne garantit donc rien : la page 3 répond 200 avec un JSON illisible, et les pages 2, 3,
5 et 6 renvoient des offres non conformes dans un JSON valide.
