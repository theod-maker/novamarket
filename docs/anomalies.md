# M4 : Anomalies, détection, effet, décision

Chiffres issus de `resultats/05_anomalies.txt` (script `sql/05_anomalies.sql`).

| Anomalie | Détection | Effet | Décision |
| --- | --- | --- | --- |
| Ligne d'article en double : `order_item_id` 7 (commande 4) répétée en fin de fichier, contenu identique | `GROUP BY order_item_id` : toute ligne autre que la première (`MIN(source_row)`) est un doublon | CA des commandes terminées gonflé de 33,75 € (26 243,75 € au lieu de 26 210,00 €) ; commande 4 à 87,50 € d'articles contre 53,75 € payés | Rejet `doublon`, 1re occurrence conservée |
| Ligne d'article orpheline : `order_item_id` 801 vers la commande 9999 inexistante | `NOT EXISTS` sur `core.orders` | 6,25 € non rattachables à un client ni à un statut | Rejet `commande inexistante`, à signaler à la source |
| Paiements identiques : 27 groupes (même commande, date, montant) | `GROUP BY ... HAVING COUNT(*) > 1` puis comparaison au total des articles | Aucun doublon : dans les 27 cas, la somme des deux paiements égale le montant des articles. Un `DISTINCT` aurait retiré à tort 27 paiements | Paiements conservés : ce sont des règlements fractionnés (`payment_id` distincts) |
| Multiplication des lignes : jointure directe articles × paiements | Comparaison jointure directe / agrégation par commande | 720 lignes au lieu de 320 commandes ; articles 29 472,50 € au lieu de 26 210,00 €, paiements 52 420,00 € au lieu de 26 210,00 € | Toujours agréger chaque table au grain commande avant de joindre |
| Périmètre du CA selon le statut | CA par périmètre de statut | 26 210,00 € (completed), 29 433,75 € (+ pending), 32 717,50 € (tous) | CA retenu = commandes `completed` uniquement |
| Commandes annulées mais encaissées : 40 commandes, 80 paiements `captured` | Jointure `orders.status = 'cancelled'` et `payments.status = 'captured'` | 3 283,75 € encaissés sans remboursement présent dans les sources | Exclues du CA ; hypothèse de remboursement non tracé à confirmer avec NovaMarket |
| 30 clients sans commande | `NOT EXISTS` sur `core.orders` | Aucun effet sur le CA ; biaise un panier moyen « par client » | Conservés en `core.customers` (pas une erreur) |

Aucune anomalie de type, de valeur manquante, de date ou de montant négatif dans les quatre sources.
