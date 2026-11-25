SELECT offer_id, observed_on, count(*) AS nombre
FROM {{ ref('mart_offres_fournisseurs') }}
GROUP BY offer_id, observed_on
HAVING count(*) > 1
