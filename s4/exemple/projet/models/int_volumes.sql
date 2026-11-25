{{ config(materialized='ephemeral') }}

select cuve, count(*) as nombre_releves, sum(volume_litres) as total_litres
from {{ ref('stg_releves') }}
group by cuve
