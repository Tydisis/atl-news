from __future__ import annotations

import asyncio
import logging
import time
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
DEFAULT_TTL_SECONDS = 300  # 5 minutes


class FeedCache:
    """In-memory TTL cache of fetched articles, keyed by Source.id."""

    def __init__(self, ttl_seconds: int = DEFAULT_TTL_SECONDS) -> None:
        self._ttl = ttl_seconds
        self._articles: list[Article] = []
        self._fetched_at: float = 0.0
        self._lock = asyncio.Lock()

    @property
    def is_fresh(self) -> bool:
        return (time.time() - self._fetched_at) < self._ttl and bool(self._articles)

    @property
    def fetched_at(self) -> datetime | None:
        if not self._fetched_at:
            return None
        return datetime.fromtimestamp(self._fetched_at, tz=timezone.utc)

    async def get_articles(self) -> list[Article]:
        if self.is_fresh:
            return self._articles
        async with self._lock:
            if self.is_fresh:
                return self._articles
            self._articles = await fetch_all(SOURCES)
            self._fetched_at = time.time()
            return self._articles

    async def refresh(self) -> list[Article]:
        async with self._lock:
            self._articles = await fetch_all(SOURCES)
            self._fetched_at = time.time()
            return self._articles


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


async def fetch_all(sources: tuple[Source, ...]) -> list[Article]:
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

    # Sort newest first; articles without a date sink to the bottom.
    deduped.sort(
        key=lambda a: a.published_at or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True,
    )
    return deduped
