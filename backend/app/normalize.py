from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any

from dateutil import parser as dateparser

from .models import Article
from .sources import Source


def _article_id(url: str) -> str:
    return hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]


def _parse_published(entry: dict[str, Any]) -> datetime | None:
    # feedparser populates *_parsed structs; fall back to raw strings if missing.
    for key in ("published_parsed", "updated_parsed"):
        struct = entry.get(key)
        if struct:
            return datetime(*struct[:6], tzinfo=timezone.utc)
    for key in ("published", "updated", "pubDate"):
        raw = entry.get(key)
        if raw:
            try:
                dt = dateparser.parse(raw)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                return dt
            except (ValueError, TypeError):
                continue
    return None


def _clean_summary(entry: dict[str, Any]) -> str | None:
    raw = entry.get("summary") or entry.get("description")
    if not raw:
        return None
    # feedparser sometimes returns dict-like for summary_detail; prefer plain text.
    if isinstance(raw, dict):
        raw = raw.get("value", "")
    # Strip very long summaries; keep it reasonable for a list view.
    text = str(raw).strip()
    return text[:500] if text else None


def entry_to_article(entry: dict[str, Any], source: Source) -> Article | None:
    url = entry.get("link")
    title = entry.get("title")
    if not url or not title:
        return None
    return Article(
        id=_article_id(url),
        title=str(title).strip(),
        url=str(url),
        summary=_clean_summary(entry),
        source_id=source.id,
        source_name=source.name,
        category=source.category,
        published_at=_parse_published(entry),
    )
