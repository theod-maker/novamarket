"""Collecte asynchrone, paginée et bornée des offres fournisseur."""
import argparse
import asyncio
import json
import os
import time
from pathlib import Path

import aiohttp

from journalisation import creer_journal, ecrire_bilan, ecrire_jsonl
from validation import charger_produits, trier_offres

DOSSIER_INGESTION = Path(__file__).resolve().parent.parent
DOSSIER_DONNEES = DOSSIER_INGESTION / "data"
FICHIER_PRODUITS = DOSSIER_INGESTION.parent / "s2" / "donnees" / "products.csv"
TENTATIVES_MAX = 4
TIMEOUT_SECONDES = 1.0
ATTENTE_MAX_SECONDES = 5.0
STATUTS_TRANSITOIRES = {429, 500, 502, 503, 504}


def lire_arguments():
    parser = argparse.ArgumentParser(description="Collecte des offres fournisseur NovaMarket")
    parser.add_argument("--scenario", choices=["clean", "atelier", "panne"], default="atelier")
    parser.add_argument("--run", required=True, help="identifiant de l'essai, ex. atelier01")
    parser.add_argument("--concurrence", type=int, default=3, help="appels HTTP simultanés")
    return parser.parse_args()


def delai_avant_reprise(tentative, retry_after):
    if retry_after is not None and retry_after.isdigit():
        return min(float(retry_after), ATTENTE_MAX_SECONDES)
    return min(0.2 * 2 ** (tentative - 1), ATTENTE_MAX_SECONDES)


def page_conforme(contenu, page):
    return (isinstance(contenu, dict) and contenu.get("page") == page
            and isinstance(contenu.get("items"), list)
            and isinstance(contenu.get("total_pages"), int))


async def appeler_api(session, limite, url, parametres, essai):
    async with limite:
        essai["en_cours"] += 1
        essai["max_en_cours"] = max(essai["max_en_cours"], essai["en_cours"])
        try:
            async with session.get(url, params=parametres) as reponse:
                return reponse.status, await reponse.text(), reponse.headers.get("Retry-After")
        finally:
            essai["en_cours"] -= 1


def lire_json(corps):
    try:
        return json.loads(corps)
    except json.JSONDecodeError:
        return None


async def lire_page(session, limite, url, page, essai):
    parametres = {"page": page, "scenario": essai["scenario"], "run": essai["run"]}
    journal = essai["journal"]
    for tentative in range(1, TENTATIVES_MAX + 1):
        essai["requetes"] += 1
        statut, corps, retry_after = None, None, None
        try:
            statut, corps, retry_after = await appeler_api(session, limite, url, parametres, essai)
        except (TimeoutError, aiohttp.ClientError) as erreur:
            journal.warning("page=%s tentative=%s erreur=%s", page, tentative,
                            type(erreur).__name__)
        essai["bruts"].append({"page": page, "tentative": tentative, "statut": statut,
                               "corps": corps})
        if statut == 200:
            contenu = lire_json(corps)
            if page_conforme(contenu, page):
                journal.info("page=%s tentative=%s offres=%s", page, tentative,
                             len(contenu["items"]))
                essai["pages_recues"] += 1
                return contenu
            motif = "json invalide" if contenu is None else "structure non conforme"
            journal.warning("page=%s tentative=%s erreur=%s", page, tentative, motif)
        elif statut is not None and statut not in STATUTS_TRANSITOIRES:
            raise RuntimeError(f"page {page} : statut {statut}, erreur permanente")
        elif statut is not None:
            journal.warning("page=%s tentative=%s statut=%s", page, tentative, statut)
        if tentative < TENTATIVES_MAX:
            await asyncio.sleep(delai_avant_reprise(tentative, retry_after))
    raise RuntimeError(f"page {page} : echec apres {TENTATIVES_MAX} tentatives")


async def collecter(url, concurrence, essai):
    limite = asyncio.Semaphore(concurrence)
    timeout = aiohttp.ClientTimeout(total=TIMEOUT_SECONDES)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        premiere = await lire_page(session, limite, url, 1, essai)
        total_pages = premiere["total_pages"]
        suivantes = await asyncio.gather(
            *(lire_page(session, limite, url, page, essai) for page in range(2, total_pages + 1)),
            return_exceptions=True)
    erreurs = [resultat for resultat in suivantes if isinstance(resultat, Exception)]
    if erreurs:
        raise RuntimeError("; ".join(str(erreur) for erreur in erreurs))
    pages = [premiere] + suivantes
    if pages[-1]["next_page"] is not None:
        raise RuntimeError("la derniere page annonce encore une page suivante")
    return pages


def publier_offres(valides):
    chemin = DOSSIER_DONNEES / "valid" / "offres.jsonl"
    provisoire = chemin.with_suffix(".jsonl.tmp")
    ecrire_jsonl(provisoire, valides)
    provisoire.replace(chemin)


def main():
    arguments = lire_arguments()
    journal = creer_journal(DOSSIER_DONNEES / "logs", arguments.run)
    essai = {"scenario": arguments.scenario, "run": arguments.run, "journal": journal,
             "requetes": 0, "pages_recues": 0, "en_cours": 0, "max_en_cours": 0,
             "bruts": []}
    port = int(os.environ.get("NOVAMARKET_API_PORT", "18080"))
    url = f"http://127.0.0.1:{port}/offers"
    journal.info("debut run=%s scenario=%s concurrence=%s", arguments.run,
                 arguments.scenario, arguments.concurrence)
    debut = time.perf_counter()
    try:
        pages = asyncio.run(collecter(url, arguments.concurrence, essai))
    except RuntimeError as erreur:
        pages = None
        journal.error("collecte interrompue, aucun lot publie : %s", erreur)
    duree = round(time.perf_counter() - debut, 3)
    bruts = sorted(essai["bruts"], key=lambda brut: (brut["page"], brut["tentative"]))
    ecrire_jsonl(DOSSIER_DONNEES / "raw" / f"{arguments.run}.jsonl", bruts)

    pages_recues = essai["pages_recues"]
    bilan = {"run": arguments.run, "scenario": arguments.scenario,
             "concurrence": arguments.concurrence,
             "appels_simultanes_max": essai["max_en_cours"], "statut": "echec",
             "pages_recues": pages_recues, "requetes_http": essai["requetes"],
             "reprises": essai["requetes"] - pages_recues, "duree_secondes": duree}
    if pages is not None:
        valides, rejets = trier_offres(pages, charger_produits(FICHIER_PRODUITS))
        ecrire_jsonl(DOSSIER_DONNEES / "rejected" / f"{arguments.run}.jsonl", rejets)
        publier_offres(valides)
        lignes_vues = sum(len(contenu["items"]) for contenu in pages)
        bilan.update(statut="complet", lignes_vues=lignes_vues, valides=len(valides),
                     rejetees=len(rejets),
                     controle_ok=lignes_vues == len(valides) + len(rejets))
    ecrire_bilan(DOSSIER_DONNEES / "bilans" / f"{arguments.run}.json", bilan)
    journal.info("bilan %s", json.dumps(bilan, ensure_ascii=False))
    return 0 if bilan["statut"] == "complet" else 1


if __name__ == "__main__":
    raise SystemExit(main())
