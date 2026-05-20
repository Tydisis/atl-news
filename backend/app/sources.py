"""Verified RSS sources. URLs were checked live before being added here."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Category = Literal["local", "state", "national"]


@dataclass(frozen=True)
class Source:
    id: str
    name: str
    category: Category
    url: str


SOURCES: tuple[Source, ...] = (
    # Local Atlanta
    Source(
        id="ajc",
        name="Atlanta Journal-Constitution",
        category="local",
        # AJC has no public RSS; Google News query is the reliable proxy.
        url="https://news.google.com/rss/search?q=site:ajc.com&hl=en-US&gl=US&ceid=US:en",
    ),
    Source(
        id="11alive",
        name="11Alive (WXIA)",
        category="local",
        url="https://www.11alive.com/feeds/syndication/rss/news/local",
    ),
    Source(
        id="wsbtv",
        name="WSB-TV",
        category="local",
        url="https://www.wsbtv.com/arc/outboundfeeds/rss/?outputType=xml",
    ),
    Source(
        id="fox5atlanta",
        name="FOX 5 Atlanta",
        category="local",
        url="https://www.fox5atlanta.com/rss/category/news",
    ),
    # State (Georgia)
    Source(
        id="gpb",
        name="Georgia Public Broadcasting",
        category="state",
        url="https://www.gpb.org/rss",
    ),
    Source(
        id="ga-politics-google",
        name="Georgia Politics (Google News)",
        category="state",
        url="https://news.google.com/rss/search?q=Georgia+politics&hl=en-US&gl=US&ceid=US:en",
    ),
    # National politics
    Source(
        id="nyt-politics",
        name="NYT Politics",
        category="national",
        url="https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml",
    ),
    Source(
        id="wapo-politics",
        name="Washington Post Politics",
        category="national",
        url="https://feeds.washingtonpost.com/rss/politics",
    ),
    Source(
        id="politico",
        name="Politico",
        category="national",
        # politico.com is Cloudflare-protected; rss.politico.com works.
        url="https://rss.politico.com/politics-news.xml",
    ),
    Source(
        id="npr-politics",
        name="NPR Politics",
        category="national",
        url="https://feeds.npr.org/1014/rss.xml",
    ),
    Source(
        id="ap-politics",
        name="AP Politics (Google News)",
        category="national",
        # feeds.apnews.com DNS is unreliable; Google News is the stable proxy.
        url="https://news.google.com/rss/search?q=site:apnews.com+politics&hl=en-US&gl=US&ceid=US:en",
    ),
)


def by_category(category: Category | None = None) -> tuple[Source, ...]:
    if category is None:
        return SOURCES
    return tuple(s for s in SOURCES if s.category == category)
