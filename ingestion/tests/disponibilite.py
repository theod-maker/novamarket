"""Contrôle HTTP minimal qui n'exécute aucun collecteur."""
import json
import os
from urllib.request import urlopen

url = f"http://127.0.0.1:{int(os.environ.get('NOVAMARKET_API_PORT', '18080'))}"
with urlopen(url + "/health", timeout=3) as response:
    assert json.load(response) == {"status": "ok"}
print("API disponible")
