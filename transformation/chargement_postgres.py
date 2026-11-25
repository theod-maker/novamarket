"""Chargement des offres valides de la S3 dans PostgreSQL."""
import json
import os
import sys
from datetime import date
from pathlib import Path

import psycopg

# Le fichier produit par le collecteur S3
FICHIER_OFFRES = Path(__file__).parent.parent / "ingestion" / "data" / "valid" / "offres.jsonl"

# Les 7 champs attendus et les fournisseurs connus de l'API
CHAMPS = ["offer_id", "supplier_id", "product_id", "price_cents", "currency",
          "available_units", "observed_on"]
FOURNISSEURS = {"F01", "F02", "F03"}

# Grain : une offre d'un fournisseur observée à une date -> clé (offer_id, observed_on)
CREATION_TABLE = """
CREATE SCHEMA IF NOT EXISTS fournisseur;
CREATE TABLE IF NOT EXISTS fournisseur.offres (
    offer_id text NOT NULL,
    observed_on date NOT NULL,
    supplier_id text NOT NULL,
    product_id integer NOT NULL,
    price_cents integer NOT NULL CHECK (price_cents >= 0),
    currency text NOT NULL CHECK (currency = 'EUR'),
    available_units integer NOT NULL CHECK (available_units >= 0),
    PRIMARY KEY (offer_id, observed_on)
);
"""

# Si l'offre existe déjà pour cette date (même clé), on ne fait rien : pas de doublon
INSERTION = """
INSERT INTO fournisseur.offres (offer_id, observed_on, supplier_id, product_id,
                                price_cents, currency, available_units)
VALUES (%(offer_id)s, %(observed_on)s, %(supplier_id)s, %(product_id)s,
        %(price_cents)s, %(currency)s, %(available_units)s)
ON CONFLICT (offer_id, observed_on) DO NOTHING
"""


# Lit le fichier JSONL : une offre par ligne
def lire_offres(chemin):
    with open(chemin, encoding="utf-8") as fichier:
        return [json.loads(ligne) for ligne in fichier]


# Les numéros de produits qui existent dans le catalogue S2 (table core.products)
def lire_produits(connexion):
    lignes = connexion.execute("SELECT product_id FROM core.products").fetchall()
    return {ligne[0] for ligne in lignes}


# Renvoie None si l'offre est bonne, sinon la raison du rejet
def controler_offre(offre, produits):
    for champ in CHAMPS:
        if champ not in offre:
            return f"champ manquant : {champ}"
    if offre["product_id"] not in produits:
        return "produit inconnu"
    if offre["supplier_id"] not in FOURNISSEURS:
        return "fournisseur inconnu"
    if offre["currency"] != "EUR":
        return "devise invalide"
    if not isinstance(offre["price_cents"], int) or offre["price_cents"] < 0:
        return "prix invalide"
    if not isinstance(offre["available_units"], int) or offre["available_units"] < 0:
        return "unites invalides"
    try:
        # Conversion du texte "2026-11-24" en vraie date
        offre["observed_on"] = date.fromisoformat(offre["observed_on"])
    except (TypeError, ValueError):
        return "date invalide"
    return None


# Insère chaque offre et compte celles vraiment ajoutées
def inserer_offres(connexion, offres):
    inserees = 0
    for offre in offres:
        resultat = connexion.execute(INSERTION, offre)
        inserees += resultat.rowcount
    return inserees


if __name__ == "__main__":
    # On peut donner un autre fichier en argument (utile pour tester), sinon celui de la S3
    chemin = sys.argv[1] if len(sys.argv) > 1 else FICHIER_OFFRES
    offres = lire_offres(chemin)
    print(len(offres), "offres lues dans", chemin)

    try:
        # Connexion avec l'adresse NOVAMARKET_DSN ; le mot de passe vient de PGPASSWORD.
        # Tout le bloc "with" est UNE transaction : COMMIT à la fin, ROLLBACK si une erreur survient
        with psycopg.connect(os.environ["NOVAMARKET_DSN"]) as connexion:
            connexion.execute(CREATION_TABLE)
            produits = lire_produits(connexion)

            # On trie : les bonnes offres d'un côté, les rejets (avec la raison) de l'autre
            valides = []
            rejets = []
            for offre in offres:
                motif = controler_offre(offre, produits)
                if motif is None:
                    valides.append(offre)
                else:
                    rejets.append((offre.get("offer_id"), motif))

            inserees = inserer_offres(connexion, valides)
    except psycopg.Error as erreur:
        print("ECHEC : chargement annule, aucune offre ecrite ->", erreur)
        raise SystemExit(1)

    print("valides :", len(valides), "/ rejetees :", len(rejets))
    print("inserees :", inserees, "/ deja presentes :", len(valides) - inserees)
    for offer_id, motif in rejets:
        print("  rejet", offer_id, ":", motif)
