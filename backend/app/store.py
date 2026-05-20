from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Protocol

from .config import Settings
from .models import Article, Category

logger = logging.getLogger(__name__)

ARTICLE_TTL_SECONDS = 24 * 60 * 60


class Store(Protocol):
    async def put_articles(self, articles: list[Article]) -> None: ...
    async def get_articles(self, category: Category | None = None, limit: int = 100) -> list[Article]: ...
    async def last_updated(self) -> datetime | None: ...


class MemoryStore:
    def __init__(self) -> None:
        self._articles: list[Article] = []
        self._last_updated: datetime | None = None

    async def put_articles(self, articles: list[Article]) -> None:
        self._articles = articles
        self._last_updated = datetime.now(timezone.utc)

    async def get_articles(self, category: Category | None = None, limit: int = 100) -> list[Article]:
        items = self._articles
        if category:
            items = [a for a in items if a.category == category]
        return items[:limit]

    async def last_updated(self) -> datetime | None:
        return self._last_updated


class DynamoStore:
    """Single-table design.

    Schema:
      PK   pk                             SK   sk                          GSI1PK              GSI1SK
      ARTICLE                                  <published_at>#<id>         CAT#<category>      <published_at>#<id>
      META                                     LAST_UPDATED                 -                    -
    """

    META_PK = "META"
    META_SK_LAST_UPDATED = "LAST_UPDATED"

    def __init__(self, settings: Settings) -> None:
        import boto3

        self._table_name = settings.dynamodb_table
        self._dynamodb = boto3.resource(
            "dynamodb",
            region_name=settings.aws_region,
            endpoint_url=settings.dynamodb_endpoint_url,
        )
        self._table = self._dynamodb.Table(self._table_name)

    async def put_articles(self, articles: list[Article]) -> None:
        import asyncio

        await asyncio.to_thread(self._put_articles_sync, articles)

    def _put_articles_sync(self, articles: list[Article]) -> None:
        now = datetime.now(timezone.utc)
        expires_at = int(time.time()) + ARTICLE_TTL_SECONDS
        with self._table.batch_writer() as batch:
            for article in articles:
                published = article.published_at or datetime.min.replace(tzinfo=timezone.utc)
                sk = f"{published.isoformat()}#{article.id}"
                batch.put_item(
                    Item={
                        "pk": "ARTICLE",
                        "sk": sk,
                        "gsi1pk": f"CAT#{article.category}",
                        "gsi1sk": sk,
                        "id": article.id,
                        "title": article.title,
                        "url": article.url,
                        "summary": article.summary or "",
                        "source_id": article.source_id,
                        "source_name": article.source_name,
                        "category": article.category,
                        "published_at": article.published_at.isoformat() if article.published_at else "",
                        "expires_at": expires_at,
                    }
                )
            batch.put_item(
                Item={
                    "pk": self.META_PK,
                    "sk": self.META_SK_LAST_UPDATED,
                    "value": now.isoformat(),
                }
            )
        logger.info("wrote %d articles to dynamodb table %s", len(articles), self._table_name)

    async def get_articles(self, category: Category | None = None, limit: int = 100) -> list[Article]:
        import asyncio

        return await asyncio.to_thread(self._get_articles_sync, category, limit)

    def _get_articles_sync(self, category: Category | None, limit: int) -> list[Article]:
        from boto3.dynamodb.conditions import Key

        if category:
            response = self._table.query(
                IndexName="gsi1",
                KeyConditionExpression=Key("gsi1pk").eq(f"CAT#{category}"),
                ScanIndexForward=False,
                Limit=limit,
            )
        else:
            response = self._table.query(
                KeyConditionExpression=Key("pk").eq("ARTICLE"),
                ScanIndexForward=False,
                Limit=limit,
            )
        return [self._item_to_article(i) for i in response.get("Items", [])]

    @staticmethod
    def _item_to_article(item: dict) -> Article:
        published_at = item.get("published_at") or None
        return Article(
            id=item["id"],
            title=item["title"],
            url=item["url"],
            summary=item.get("summary") or None,
            source_id=item["source_id"],
            source_name=item["source_name"],
            category=item["category"],
            published_at=datetime.fromisoformat(published_at) if published_at else None,
        )

    async def last_updated(self) -> datetime | None:
        import asyncio

        return await asyncio.to_thread(self._last_updated_sync)

    def _last_updated_sync(self) -> datetime | None:
        response = self._table.get_item(Key={"pk": self.META_PK, "sk": self.META_SK_LAST_UPDATED})
        item = response.get("Item")
        if not item:
            return None
        return datetime.fromisoformat(item["value"])


def make_store(settings: Settings) -> Store:
    if settings.store_backend == "dynamodb":
        return DynamoStore(settings)
    return MemoryStore()
