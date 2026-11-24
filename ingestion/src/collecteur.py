"""Collecte asynchrone des offres fournisseur NovaMarket."""
import argparse
import asyncio
import json
import time
from pathlib import Path

import aiohttp

from journalisation import creer_journal, ecrire_bilan, ecrire_jsonl
from validation import charger_produits, trier_offres

URL = "http://127.0.0.1:18080/offers"
DOSSIER_DATA = Path(__file__).parent.parent / "data"
CATALOGUE = Path(__file__).parent.parent.parent / "s2" / "donnees" / "products.csv"
TENTATIVES_MAX = 4
TIMEOUT_SECONDES = 1


async def lire_page(session, limite, page, essai):
    journal = essai["journal"]
    parametres = {"page": page, "scenario": essai["scenario"], "run": essai["run"]}
    for tentative in range(1, TENTATIVES_MAX + 1):
        essai["requetes"] += 1
        attente = 0.2 * 2 ** (tentative - 1)
        try:
            async with limite:
                async with session.get(URL, params=parametres) as reponse:
                    statut = reponse.status
                    corps = await reponse.text()
                    retry_after = reponse.headers.get("Retry-After")
            essai["bruts"].append({"page": page, "tentative": tentative,
                                   "statut": statut, "corps": corps})
            if statut == 200:
                contenu = json.loads(corps)
                journal.info("page=%s tentative=%s ok", page, tentative)
                return contenu
            journal.warning("page=%s tentative=%s statut=%s", page, tentative, statut)
            if statut == 429 and retry_after:
                attente = int(retry_after)
            elif statut < 500:
                raise RuntimeError(f"page {page} : erreur {statut}, inutile de reessayer")
        except json.JSONDecodeError:
            journal.warning("page=%s tentative=%s json invalide", page, tentative)
        except (TimeoutError, aiohttp.ClientError) as erreur:
            journal.warning("page=%s tentative=%s %s", page, tentative, type(erreur).__name__)
        if tentative < TENTATIVES_MAX:
            await asyncio.sleep(attente)
    raise RuntimeError(f"page {page} : echec apres {TENTATIVES_MAX} tentatives")


async def collecter(concurrence, essai):
    limite = asyncio.Semaphore(concurrence)
    timeout = aiohttp.ClientTimeout(total=TIMEOUT_SECONDES)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        premiere = await lire_page(session, limite, 1, essai)
        autres = await asyncio.gather(
            *(lire_page(session, limite, page, essai)
              for page in range(2, premiere["total_pages"] + 1)))
    return [premiere] + autres


def main():
    parser = argparse.ArgumentParser(description="Collecte des offres fournisseur")
    parser.add_argument("--scenario", choices=["clean", "atelier", "panne"], default="atelier")
    parser.add_argument("--run", required=True)
    parser.add_argument("--concurrence", type=int, default=3)
    arguments = parser.parse_args()

    journal = creer_journal(DOSSIER_DATA / "logs", arguments.run)
    essai = {"scenario": arguments.scenario, "run": arguments.run, "journal": journal,
             "requetes": 0, "bruts": []}
    debut = time.perf_counter()
    try:
        pages = asyncio.run(collecter(arguments.concurrence, essai))
    except RuntimeError as erreur:
        journal.error("collecte interrompue, aucun lot publie : %s", erreur)
        pages = None
    duree = round(time.perf_counter() - debut, 2)
    ecrire_jsonl(DOSSIER_DATA / "raw" / f"{arguments.run}.jsonl", essai["bruts"])

    bilan = {"run": arguments.run, "scenario": arguments.scenario,
             "concurrence": arguments.concurrence, "requetes_http": essai["requetes"],
             "duree_secondes": duree, "statut": "echec"}
    if pages is not None:
        valides, rejets = trier_offres(pages, charger_produits(CATALOGUE))
        ecrire_jsonl(DOSSIER_DATA / "valid" / "offres.jsonl", valides)
        ecrire_jsonl(DOSSIER_DATA / "rejected" / f"{arguments.run}.jsonl", rejets)
        bilan.update(statut="complet", pages=len(pages),
                     reprises=essai["requetes"] - len(pages),
                     lignes_vues=sum(len(contenu["items"]) for contenu in pages),
                     valides=len(valides), rejetees=len(rejets))
    ecrire_bilan(DOSSIER_DATA / "bilans" / f"{arguments.run}.json", bilan)
    journal.info("bilan %s", bilan)
    return 0 if bilan["statut"] == "complet" else 1


if __name__ == "__main__":
    raise SystemExit(main())
