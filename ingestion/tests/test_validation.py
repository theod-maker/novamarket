"""Tests des règles de validation, sans appel à l'API."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from validation import motif_rejet, trier_offres

PRODUITS = {1, 2, 3}
BONNE_OFFRE = {"offer_id": "O001", "supplier_id": "F01", "product_id": 1, "price_cents": 625,
               "currency": "EUR", "available_units": 2, "observed_on": "2026-11-24"}


def modifier(**changements):
    return {**BONNE_OFFRE, **changements}


sans_fournisseur = dict(BONNE_OFFRE)
del sans_fournisseur["supplier_id"]

assert motif_rejet(BONNE_OFFRE, PRODUITS, set()) is None
assert motif_rejet(sans_fournisseur, PRODUITS, set()) == "champ manquant : supplier_id"
assert motif_rejet(modifier(price_cents="inconnu"), PRODUITS, set()) == "prix invalide"
assert motif_rejet(modifier(price_cents=-1), PRODUITS, set()) == "prix invalide"
assert motif_rejet(modifier(available_units=-2), PRODUITS, set()) == "unites invalides"
assert motif_rejet(modifier(currency="USD"), PRODUITS, set()) == "devise invalide"
assert motif_rejet(modifier(observed_on="2026-02-30"), PRODUITS, set()) == "date invalide"
assert motif_rejet(modifier(product_id=9999), PRODUITS, set()) == "produit inexistant"
assert motif_rejet(BONNE_OFFRE, PRODUITS, {"O001"}) == "doublon"

pages = [{"page": 1, "items": [BONNE_OFFRE, modifier(offer_id="O002", price_cents="inconnu")]},
         {"page": 2, "items": [BONNE_OFFRE]}]
valides, rejets = trier_offres(pages, PRODUITS)
assert valides == [BONNE_OFFRE]
assert [(r["page"], r["position"], r["motif"]) for r in rejets] == [
    (1, 2, "prix invalide"), (2, 1, "doublon")]

print("tests de validation OK")
