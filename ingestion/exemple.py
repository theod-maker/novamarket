"""Exemple sur une mesure de cuve indépendante des offres fournisseurs."""
import asyncio
import logging
import os

import aiohttp


async def mesure(session, limite, url):
    for essai in range(2):
        try:
            async with limite:
                async with session.get(url) as response:
                    response.raise_for_status()
                    return await response.json()
        except (TimeoutError, aiohttp.ClientError):
            logging.warning("Mesure indisponible, essai %s", essai + 1)
            if essai == 1:
                raise
            await asyncio.sleep(.3)


async def main():
    port = int(os.environ.get("NOVAMARKET_API_PORT", "18080"))
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=2)) as session:
        limite = asyncio.Semaphore(2)
        print(await asyncio.gather(*(mesure(session, limite, f"http://127.0.0.1:{port}/demo")
                                     for _ in range(3))))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
