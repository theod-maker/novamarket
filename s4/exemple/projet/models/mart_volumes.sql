{{ config(materialized='table') }}

select cuve, nombre_releves, total_litres
from {{ ref('int_volumes') }}
