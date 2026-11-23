# M1 — Modèle relationnel NovaMarket

## Grain des sources

| Source | Une ligne représente | Clé | Relation |
| --- | --- | --- | --- |
| `customers.csv` | un client | `customer_id` | 1 client → N commandes |
| `orders.csv` | une commande | `order_id` | 1 commande → N articles, N paiements |
| `order_items.csv` | une ligne d'article d'une commande | `order_item_id` | N lignes → 1 commande |
| `payments.ndjson` | une opération de paiement | `payment_id` | N paiements → 1 commande |

`products.csv` et `categories.csv` sont hors périmètre S1 : `product_id` est conservé sans clé
étrangère vers un catalogue.

## Schéma

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : passe
    ORDERS ||--|{ ORDER_ITEMS : contient
    ORDERS ||--o{ PAYMENTS : "est réglée par"

    CUSTOMERS {
        integer customer_id PK
        text customer_name "NOT NULL"
        text city "NOT NULL"
    }
    ORDERS {
        integer order_id PK
        integer customer_id FK "NOT NULL"
        date ordered_on "NOT NULL"
        text status "completed | pending | cancelled"
    }
    ORDER_ITEMS {
        integer order_item_id PK
        integer order_id FK "NOT NULL"
        integer product_id "NOT NULL, catalogue hors S1"
        integer quantity "CHECK > 0"
        integer unit_price_cents "CHECK >= 0"
    }
    PAYMENTS {
        integer payment_id PK
        integer order_id FK "NOT NULL"
        date paid_on "NOT NULL"
        integer amount_cents "CHECK > 0"
        text status "captured | pending"
    }
```

## Trois couches

| Schéma | Rôle | Contraintes |
| --- | --- | --- |
| `reception` | copie brute des fichiers, toutes les colonnes en `text`, numéro de ligne `source_row` | aucune : rien n'est perdu au chargement |
| `quality` | `rejected_rows` : fichier, ligne, clé, cause du rejet, enregistrement brut en `jsonb` | une ligne source rejetée une seule fois |
| `core` | données métier typées et fiables, utilisées par les indicateurs | clés primaires, clés étrangères, `NOT NULL`, `CHECK` |

Ordre d'intégration imposé par les clés étrangères : `customers`, `orders`, puis `order_items` et
`payments`.

## Choix de conception justifiés

1. **Réception en `text` sans contrainte.** Un `\copy` direct dans une table contrainte échoue à
   la première anomalie (doublon de clé de `order_item_id` 7) et annule tout le fichier. En
   réception, les 802 lignes sont chargées ; chaque ligne est ensuite contrôlée (champ manquant,
   type, domaine, doublon, référence orpheline) et part soit en `core`, soit en
   `quality.rejected_rows` avec sa cause. Le contrôle `reçues = intégrées + rejetées` le prouve.
2. **Montants en centimes `integer`.** Les sources sont en centimes : un entier évite toute erreur
   d'arrondi des flottants et garde le montant exact. La conversion en euros (`/ 100.0`) n'a lieu
   qu'à l'affichage des indicateurs.
3. **Statuts en `text` avec `CHECK`** plutôt qu'un type `ENUM` : la liste est contrôlée et sensible
   à la casse, comme l'indique le dictionnaire, et reste modifiable sans `ALTER TYPE`.
4. **Doublons départagés par `source_row`.** Pour une même clé, la première occurrence valide est
   gardée ; les suivantes sont rejetées en `duplicate_exact` (contenu identique) ou
   `duplicate_id_conflict` (contenu différent, à arbitrer avec le métier).
5. **Paiements gardés au grain de l'opération.** Une commande peut avoir plusieurs paiements :
   aucune déduplication sur (commande, date, montant), voir `anomalies.md`.
