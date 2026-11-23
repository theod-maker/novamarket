# Sources NovaMarket S1

Les fichiers représentent des données fictives et utilisent UTF-8, des dates ISO `AAAA-MM-JJ` et des montants en centimes d'euro. Les CSV ont une ligne d'en-tête et la virgule comme séparateur. Le NDJSON contient un objet JSON par ligne. Les codes d'état sont sensibles à la casse.

| Fichier | Grain et colonnes |
| --- | --- |
| `customers.csv` | Une fiche client. `customer_id` identifiant stable, `customer_name` nom fictif, `city` ville. |
| `orders.csv` | Une commande. `order_id` identifiant, `customer_id` client indiqué par la source, `ordered_on` date de commande, `status` parmi `completed` (terminée), `pending` (en attente) et `cancelled` (annulée). |
| `order_items.csv` | Une ligne d'article reçue. `order_item_id` identifiant de ligne, `order_id` commande indiquée, `product_id` code catalogue stable, `quantity` quantité, `unit_price_cents` prix unitaire de la transaction. Le catalogue est hors périmètre S1. |
| `payments.ndjson` | Une opération de paiement. `payment_id` identifiant, `order_id` commande indiquée, `paid_on` date de l'enregistrement, `amount_cents` montant de l'opération, `status` parmi `captured` (encaissé) et `pending` (en attente). |

Le prix de ligne reflète l'achat au moment de la transaction. Une commande peut contenir plusieurs articles et plusieurs paiements. La date d'un paiement en attente indique sa saisie. Pour les agrégations monétaires, déterminer le grain et le périmètre avant de comparer des totaux.

Catégories à examiner pendant la séance :

- Anomalies d'insertion, de mise à jour et de suppression sur l'exemple indépendant du planning d'ateliers.
- Doublons réels et références orphelines dans les sources de réception.
- Multiplication des lignes lors des jointures entre données de grains différents.
- Impact des états de commande sur le périmètre d'un chiffre d'affaires.

Conserver les fichiers bruts tels qu'ils sont fournis. Relever les volumes vus en réception, les écarts expliqués et les volumes intégrés. Le groupe choisit son schéma et justifie ses contraintes, sa stratégie d'import et ses indicateurs.
