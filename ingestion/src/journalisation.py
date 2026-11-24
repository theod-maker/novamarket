"""Journal d'exécution, fichiers JSONL et bilan de collecte."""
import json
import logging


def creer_journal(dossier, run):
    dossier.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.StreamHandler(),
                  logging.FileHandler(dossier / f"{run}.log", mode="w", encoding="utf-8")])
    return logging.getLogger("collecteur")


def ecrire_jsonl(chemin, lignes):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as fichier:
        for ligne in lignes:
            fichier.write(json.dumps(ligne, ensure_ascii=False) + "\n")


def ecrire_bilan(chemin, bilan):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as fichier:
        json.dump(bilan, fichier, ensure_ascii=False, indent=2)
