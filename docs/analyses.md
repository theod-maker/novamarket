# S2 M2 : analyses avancées

Périmètre commun : lignes de commandes au statut `completed`, montants `quantity * unit_price_cents`
(tables `core`, donc sans les rejets). Chaque requête affiche son grain de sortie dans `resultats/`.

## Classements (`sql/08_rankings.sql`)

**Produits (R1).** Une ligne par produit, CA décroissant.
- `RANK()` global, `DENSE_RANK()` global et `RANK()` dans la catégorie (`PARTITION BY category_id`).
- Ex aequo : les produits 7 et 18 font tous les deux 715,00 €. `RANK` leur donne 15 et passe ensuite
  à 17, `DENSE_RANK` leur donne 15 et continue à 16. On garde `RANK` pour le classement « officiel » :
  le 17e produit a bien 16 produits devant lui.
- 1er : produit 23 (Jeux de table, 2 733,75 €) ; dernier : produit 3 (Rangement, 236,25 €).

**Clients (R3).** Une ligne par client ayant au moins une commande terminée, classés dans leur ville
(`PARTITION BY city`), car on compare des clients d'une même zone.
- Beaucoup d'ex aequo : à Lille, 4 clients sont 1ers avec 341,25 €. Avec `RANK`, ils partagent la
  1re place. Un `ROW_NUMBER` aurait désigné un seul gagnant de façon arbitraire.

**Effet d'une duplication (R4).** Si on joint les ventes au catalogue brut (avec le doublon du
produit 3), le produit 3 passe de 236,25 € à 472,50 € et remonte de la 24e à la 21e place. Les
produits 9, 6 et 1 perdent chacun une place sans que leurs ventes aient changé.

## Évolution (`sql/09_evolution.sql`)

**Couverture des périodes (E1).** Septembre et octobre sont complets. Novembre s'arrête au 19 :
19 jours sur 30.

**Mensuel avec `LAG()` et `LEAD()` (E2).** Une ligne par mois.

| Mois | CA | Variation vs mois précédent | CA par jour | Variation par jour |
| --- | --- | --- | --- | --- |
| septembre | 9 717,50 € | | 323,92 € | |
| octobre | 10 261,25 € | +5,6 % | 331,01 € | +2,2 % |
| novembre (au 19) | 6 231,25 € | -39,3 % | 327,96 € | -0,9 % |

La baisse de 39 % en novembre n'est pas une vraie baisse : le mois est incomplet. Rapporté au nombre
de jours couverts, le CA journalier est stable (-0,9 %). C'est une évolution inhabituelle expliquée par
la couverture, pas une incohérence des données.

**Hebdomadaire (E3).** La 1re semaine (6 jours) et la dernière (4 jours) sont incomplètes : la chute de
1 113,75 € de la dernière semaine vient de là. Entre semaines complètes, les variations restent sous
±550 €. Aucune semaine ne manque (`days_since_previous_week` = 7 partout), donc `LAG` compare bien des
semaines voisines.

**Cohérence ventes / catalogue (E4).** Les seules ventes antérieures à la date de mise en vente
(produit 6) pèsent 62,50 € en septembre. Là, c'est une incohérence démontrée : une date de catalogue
postérieure à des ventes réelles.

## Requêtes en étapes avec `WITH`

Toutes les analyses S2 utilisent une CTE. Exemple (R1) : `product_revenue` agrège les lignes de
commande, une ligne par produit ; la requête finale ajoute les libellés et les rangs sans changer ce
grain. Agréger avant de joindre évite de multiplier les lignes.

## Segmentation (`sql/10_segmentation.sql`)

- **Population** : les 120 clients ayant au moins une commande terminée. Les 30 clients sans aucune
  commande et les 30 clients sans commande terminée sont exclus (S2).
- **Mesure** : CA des commandes terminées. **Ordre** : CA décroissant, puis `customer_id` pour que le
  découpage soit reproductible.
- `NTILE(4)` donne 4 groupes de 30 clients. Le 1er quart fait 35,4 % du CA, le dernier 15,8 %.
- **Égalités** : 10 clients à 206,25 € sont répartis entre Q2 et Q3, et 4 clients à 167,50 € entre Q3 et
  Q4 (S3). `NTILE` coupe au nombre de lignes, pas à la valeur : la frontière tombe au milieu de clients
  identiques, et seul l'ordre par `customer_id` les départage.

## Hiérarchie (`sql/11_hierarchy.sql`)

- `WITH RECURSIVE` part des racines (`parent_category_id IS NULL`) et descend niveau par niveau (H1).
- Contrôle des cycles : on garde le chemin parcouru (`path_ids`) et on refuse une catégorie déjà vue ;
  la profondeur est limitée à 10. Contrôle des rattachements (H2) : 10 catégories atteintes sur 10, une
  seule ligne par catégorie, profondeur maximale 2.
- **CA par famille (H3)** : Loisirs 17 966,25 € (68,5 %), Maison 8 243,75 € (31,5 %). La somme fait bien
  26 210,00 €.
- **Double comptage (H4)** : si on additionne le CA de chaque catégorie en incluant ses sous-catégories,
  un produit est compté à sa catégorie et à chacun de ses ancêtres. La somme de toutes les lignes donne
  69 006,25 €, soit 2,6 fois le vrai total. Pour comparer des familles, il faut rester à un seul niveau
  de l'arbre.

## Limites

- Trois mois seulement, dont un incomplet : les tendances restent fragiles.
- Les montants sont ceux des lignes de commande. Les commandes annulées encaissées (S1) ne sont pas
  comptées.
- Les données sont fictives et très régulières, d'où les nombreux ex aequo.
