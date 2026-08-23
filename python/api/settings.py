"""API settings loaded from environment / .env."""

from __future__ import annotations

from functools import lru_cache
from typing import List

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    neo4j_uri: str = Field(default="bolt://localhost:7687", alias="NEO4J_URI")
    neo4j_username: str = Field(default="neo4j", alias="NEO4J_USERNAME")
    neo4j_password: str = Field(default="changeme_use_vault_in_prod", alias="NEO4J_PASSWORD")
    neo4j_database: str = Field(default="neo4j", alias="NEO4J_DATABASE")
    neo4j_max_pool_size: int = Field(default=50, alias="NEO4J_MAX_POOL_SIZE")
    neo4j_connection_timeout: float = Field(default=30.0, alias="NEO4J_CONNECTION_TIMEOUT")

    api_host: str = Field(default="0.0.0.0", alias="API_HOST")
    api_port: int = Field(default=8000, alias="API_PORT")
    api_cors_origins: str = Field(
        default="http://localhost:5173", alias="API_CORS_ORIGINS"
    )
    api_read_only: bool = Field(default=True, alias="API_READ_ONLY")
    prometheus_url: str = Field(default="http://localhost:9090", alias="PROMETHEUS_URL")

    @property
    def cors_origins(self) -> List[str]:
        return [o.strip() for o in self.api_cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
