"""Journal d'exécution, fichiers JSONL et bilan de collecte."""
import json
import logging


def creer_journal(dossier_logs, run):
    dossier_logs.mkdir(parents=True, exist_ok=True)
    journal = logging.getLogger("collecteur")
    journal.setLevel(logging.INFO)
    journal.handlers.clear()
    format_ligne = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    sorties = [logging.StreamHandler(),
               logging.FileHandler(dossier_logs / f"{run}.log", mode="w", encoding="utf-8")]
    for sortie in sorties:
        sortie.setFormatter(format_ligne)
        journal.addHandler(sortie)
    return journal


def ecrire_jsonl(chemin, lignes):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as fichier:
        for ligne in lignes:
            fichier.write(json.dumps(ligne, ensure_ascii=False) + "\n")


def ecrire_bilan(chemin, bilan):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(json.dumps(bilan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
