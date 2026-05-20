from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

import feedparser
import httpx

from .models import Article
from .normalize import entry_to_article
from .sources import SOURCES, Source

logger = logging.getLogger(__name__)

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) atl-news/0.1"
)
REQUEST_TIMEOUT = 15.0


async def _fetch_one(client: httpx.AsyncClient, source: Source) -> list[Article]:
    try:
        resp = await client.get(source.url, timeout=REQUEST_TIMEOUT)
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("fetch failed for %s: %s", source.id, exc)
        return []

    parsed = feedparser.parse(resp.content)
    if parsed.bozo and not parsed.entries:
        logger.warning("malformed feed for %s: %s", source.id, parsed.bozo_exception)
        return []

    articles: list[Article] = []
    for entry in parsed.entries:
        article = entry_to_article(entry, source)
        if article is not None:
            articles.append(article)
    logger.info("fetched %d articles from %s", len(articles), source.id)
    return articles


async def fetch_all(sources: tuple[Source, ...] = SOURCES) -> list[Article]:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/rss+xml, application/xml, text/xml, */*"}
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        results = await asyncio.gather(
            *(_fetch_one(client, s) for s in sources), return_exceptions=False
        )

    seen: set[str] = set()
    deduped: list[Article] = []
    for batch in results:
        for article in batch:
            if article.url in seen:
                continue
            seen.add(article.url)
            deduped.append(article)

    deduped.sort(
        key=lambda a: a.published_at or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True,
    )
    return deduped
