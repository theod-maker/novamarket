"""Journal d'exécution, fichiers JSONL et bilan de collecte."""
import json
import logging


# Journal écrit à l'écran et dans data/logs/<run>.log
def creer_journal(dossier, run):
    dossier.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.StreamHandler(),
                  logging.FileHandler(dossier / f"{run}.log", mode="w", encoding="utf-8")])
    return logging.getLogger("collecteur")


# Un objet JSON par ligne ; le fichier est réécrit, pas complété
def ecrire_jsonl(chemin, lignes):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as fichier:
        for ligne in lignes:
            fichier.write(json.dumps(ligne, ensure_ascii=False) + "\n")


# Compteurs de l'essai dans data/bilans/<run>.json
def ecrire_bilan(chemin, bilan):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as fichier:
        json.dump(bilan, fichier, ensure_ascii=False, indent=2)
