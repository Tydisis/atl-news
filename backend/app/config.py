from __future__ import annotations

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

StoreBackend = Literal["memory", "dynamodb"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ATL_", env_file=".env", extra="ignore")

    store_backend: StoreBackend = "memory"
    dynamodb_table: str = "atl-news-articles"
    dynamodb_endpoint_url: str | None = None
    aws_region: str = "us-east-1"
    memory_refresh_interval_seconds: int = 600


def get_settings() -> Settings:
    return Settings()
