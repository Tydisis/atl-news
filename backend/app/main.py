from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import get_args

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .fetcher import FeedCache
from .models import Category, FeedResponse, SourceInfo
from .sources import SOURCES

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

VALID_CATEGORIES: tuple[str, ...] = get_args(Category)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.cache = FeedCache()
    yield


app = FastAPI(title="atl-news", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/sources", response_model=list[SourceInfo])
async def list_sources() -> list[SourceInfo]:
    return [SourceInfo(**s.__dict__) for s in SOURCES]


@app.get("/api/feed", response_model=FeedResponse)
async def get_feed(
    category: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
) -> FeedResponse:
    if category is not None and category not in VALID_CATEGORIES:
        raise HTTPException(
            status_code=400,
            detail=f"category must be one of {VALID_CATEGORIES}",
        )
    articles = await app.state.cache.get_articles()
    if category:
        articles = [a for a in articles if a.category == category]
    articles = articles[:limit]
    return FeedResponse(count=len(articles), articles=articles)


@app.post("/api/refresh", response_model=FeedResponse)
async def refresh_feed() -> FeedResponse:
    articles = await app.state.cache.refresh()
    return FeedResponse(count=len(articles), articles=articles)
