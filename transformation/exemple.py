"""Charge deux volumes de cuves avec une clé unique, sans écrire dans NovaMarket."""
import os

import psycopg

with psycopg.connect(os.environ["NOVAMARKET_DSN"], connect_timeout=5) as db:
    db.execute("CREATE TEMP TABLE cuves (id int PRIMARY KEY, litres int NOT NULL)")
    query = """INSERT INTO cuves VALUES (%s,%s)
               ON CONFLICT (id) DO UPDATE SET litres=excluded.litres
               WHERE cuves.litres IS DISTINCT FROM excluded.litres"""
    for batch in range(2):
        changes = sum(db.execute(query, row).rowcount for row in [(1, 35), (2, 42)])
        print(f"Passage {batch + 1}, changements : {changes}")
    print(db.execute("SELECT * FROM cuves ORDER BY id").fetchall())
