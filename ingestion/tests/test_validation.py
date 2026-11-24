"""Contrôle des règles de validation, sans appel à l'API."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from validation import motif_rejet, trier_offres

PRODUITS = {1, 2, 3}
OFFRE = {"offer_id": "O001", "supplier_id": "F01", "product_id": 1, "price_cents": 625,
         "currency": "EUR", "available_units": 2, "observed_on": "2026-11-24"}


def variante(**changements):
    offre = dict(OFFRE)
    offre.update(changements)
    return offre


def sans(champ):
    offre = dict(OFFRE)
    del offre[champ]
    return offre


cas = [
    (OFFRE, None),
    (sans("supplier_id"), "champ manquant : supplier_id"),
    (variante(offer_id=""), "offer_id invalide"),
    (variante(product_id="1"), "product_id non entier"),
    (variante(price_cents="inconnu"), "prix invalide"),
    (variante(price_cents=-1), "prix invalide"),
    (variante(price_cents=True), "prix invalide"),
    (variante(available_units=-2), "unites invalides"),
    (variante(currency="USD"), "devise inconnue"),
    (variante(observed_on="24/11/2026"), "date invalide"),
    (variante(observed_on="2026-02-30"), "date invalide"),
    (variante(product_id=9999), "produit inexistant"),
    ("pas un objet", "offre non objet"),
]
for offre, attendu in cas:
    obtenu = motif_rejet(offre, PRODUITS, set())
    assert obtenu == attendu, f"{offre} : attendu {attendu!r}, obtenu {obtenu!r}"

assert motif_rejet(OFFRE, PRODUITS, {"O001"}) == "doublon"

pages = [{"page": 1, "items": [OFFRE, variante(price_cents="inconnu", offer_id="O002")]},
         {"page": 2, "items": [OFFRE]}]
valides, rejets = trier_offres(pages, PRODUITS)
assert valides == [OFFRE]
assert [(rejet["page"], rejet["position"], rejet["motif"]) for rejet in rejets] == [
    (1, 2, "prix invalide"), (2, 1, "doublon")]

print(f"validation : {len(cas) + 2} controles OK")
