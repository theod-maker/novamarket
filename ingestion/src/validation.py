"""Règles de contrôle des offres fournisseur et motifs de rejet."""
import csv
from datetime import date

CHAMPS = ("offer_id", "supplier_id", "product_id", "price_cents", "currency",
          "available_units", "observed_on")


def charger_produits(chemin_csv):
    with open(chemin_csv, encoding="utf-8", newline="") as fichier:
        return {int(ligne["product_id"]) for ligne in csv.DictReader(fichier)}


def est_entier(valeur):
    return isinstance(valeur, int) and not isinstance(valeur, bool)


def est_texte_rempli(valeur):
    return isinstance(valeur, str) and valeur != ""


def est_date_iso(valeur):
    if not isinstance(valeur, str) or len(valeur) != 10:
        return False
    try:
        date.fromisoformat(valeur)
    except ValueError:
        return False
    return True


def motif_rejet(offre, produits, offres_acceptees):
    if not isinstance(offre, dict):
        return "offre non objet"
    manquants = [champ for champ in CHAMPS if champ not in offre]
    if manquants:
        return "champ manquant : " + ", ".join(manquants)
    if not est_texte_rempli(offre["offer_id"]):
        return "offer_id invalide"
    if not est_texte_rempli(offre["supplier_id"]):
        return "supplier_id invalide"
    if not est_entier(offre["product_id"]):
        return "product_id non entier"
    if not est_entier(offre["price_cents"]) or offre["price_cents"] < 0:
        return "prix invalide"
    if not est_entier(offre["available_units"]) or offre["available_units"] < 0:
        return "unites invalides"
    if offre["currency"] != "EUR":
        return "devise inconnue"
    if not est_date_iso(offre["observed_on"]):
        return "date invalide"
    if offre["product_id"] not in produits:
        return "produit inexistant"
    if offre["offer_id"] in offres_acceptees:
        return "doublon"
    return None


def trier_offres(pages, produits):
    valides = []
    rejets = []
    offres_acceptees = set()
    for contenu in pages:
        for position, offre in enumerate(contenu["items"], start=1):
            motif = motif_rejet(offre, produits, offres_acceptees)
            if motif is None:
                valides.append({champ: offre[champ] for champ in CHAMPS})
                offres_acceptees.add(offre["offer_id"])
            else:
                rejets.append({"page": contenu["page"], "position": position,
                               "motif": motif, "offre": offre})
    return valides, rejets
