from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

Category = Literal["local", "state", "national"]


class Article(BaseModel):
    id: str = Field(description="Stable hash of the article URL")
    title: str
    url: str
    summary: str | None = None
    source_id: str
    source_name: str
    category: Category
    published_at: datetime | None = None


class FeedResponse(BaseModel):
    count: int
    articles: list[Article]


class SourceInfo(BaseModel):
    id: str
    name: str
    category: Category
    url: str
