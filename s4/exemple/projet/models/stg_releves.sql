{{ config(materialized='view') }}

select releve_id, trim(cuve) as cuve, volume_litres
from {{ source('capteurs', 'releves') }}
