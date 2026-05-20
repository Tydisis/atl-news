from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import get_args

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

import asyncio

from .config import get_settings
from .fetcher import fetch_all
from .models import Category, FeedResponse, SourceInfo
from .sources import SOURCES
from .store import make_store

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("atl-news.api")

VALID_CATEGORIES: tuple[str, ...] = get_args(Category)


async def _memory_refresh_loop(store, interval: int) -> None:
    while True:
        try:
            articles = await fetch_all()
            if articles:
                await store.put_articles(articles)
                logger.info("memory store refreshed: %d articles", len(articles))
        except Exception as exc:  # noqa: BLE001
            logger.exception("background refresh failed: %s", exc)
        await asyncio.sleep(interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    app.state.settings = settings
    app.state.store = make_store(settings)
    refresh_task: asyncio.Task | None = None
    if settings.store_backend == "memory":
        articles = await fetch_all()
        await app.state.store.put_articles(articles)
        logger.info("memory store seeded with %d articles", len(articles))
        refresh_task = asyncio.create_task(
            _memory_refresh_loop(app.state.store, settings.memory_refresh_interval_seconds)
        )
    logger.info("api ready (store=%s)", settings.store_backend)
    try:
        yield
    finally:
        if refresh_task is not None:
            refresh_task.cancel()
            try:
                await refresh_task
            except asyncio.CancelledError:
                pass


app = FastAPI(title="atl-news", version="0.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz() -> dict[str, str]:
    last = await app.state.store.last_updated()
    if last is None:
        raise HTTPException(status_code=503, detail="store has no data yet")
    return {"status": "ok", "last_updated": last.isoformat()}


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
    articles = await app.state.store.get_articles(category=category, limit=limit)
    return FeedResponse(count=len(articles), articles=articles)
