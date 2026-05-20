"""Run a single fetch cycle and write to the configured store. Exits when done."""
from __future__ import annotations

import asyncio
import logging
import sys

from .config import get_settings
from .fetcher import fetch_all
from .store import make_store

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("atl-news.fetcher")


async def main() -> int:
    settings = get_settings()
    logger.info("starting fetch cycle (backend=%s)", settings.store_backend)
    store = make_store(settings)
    articles = await fetch_all()
    if not articles:
        logger.error("fetch produced 0 articles; not writing to store")
        return 1
    await store.put_articles(articles)
    logger.info("fetch complete: %d articles written", len(articles))
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
