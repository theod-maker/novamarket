WITH source_offres AS (
    SELECT count(*) AS nombre, sum(available_units) AS unites
    FROM {{ source('fournisseur', 'offres') }}
),

mart AS (
    SELECT count(*) AS nombre, sum(available_units) AS unites
    FROM {{ ref('mart_offres_fournisseurs') }}
)

SELECT source_offres.nombre, mart.nombre, source_offres.unites, mart.unites
FROM source_offres
CROSS JOIN mart
WHERE source_offres.nombre <> mart.nombre OR source_offres.unites <> mart.unites
