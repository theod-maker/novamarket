"""Règles de contrôle des offres fournisseur."""
import csv
from datetime import date

# Les 7 champs du contrat de l'API
CHAMPS = ["offer_id", "supplier_id", "product_id", "price_cents", "currency",
          "available_units", "observed_on"]


# Ensemble des product_id du catalogue S2
def charger_produits(chemin):
    with open(chemin, encoding="utf-8") as fichier:
        return {int(ligne["product_id"]) for ligne in csv.DictReader(fichier)}


# Renvoie None si l'offre est valide, sinon la raison du rejet
def motif_rejet(offre, produits, offres_vues):
    for champ in CHAMPS:
        if champ not in offre:
            return f"champ manquant : {champ}"
    if not isinstance(offre["price_cents"], int) or offre["price_cents"] < 0:
        return "prix invalide"
    if not isinstance(offre["available_units"], int) or offre["available_units"] < 0:
        return "unites invalides"
    if offre["currency"] != "EUR":
        return "devise invalide"
    try:
        date.fromisoformat(offre["observed_on"])
    except (TypeError, ValueError):
        return "date invalide"
    # Le produit doit exister dans le catalogue
    if offre["product_id"] not in produits:
        return "produit inexistant"
    # Doublon : on garde la première offre
    if offre["offer_id"] in offres_vues:
        return "doublon"
    return None


# Range chaque offre dans valides ou rejets (avec page, position, motif)
def trier_offres(pages, produits):
    valides = []
    rejets = []
    offres_vues = set()
    for contenu in pages:
        for position, offre in enumerate(contenu["items"], start=1):
            motif = motif_rejet(offre, produits, offres_vues)
            if motif is None:
                valides.append(offre)
                offres_vues.add(offre["offer_id"])
            else:
                rejets.append({"page": contenu["page"], "position": position,
                               "motif": motif, "offre": offre})
    return valides, rejets
