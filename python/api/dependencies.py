"""FastAPI dependency providers."""

from __future__ import annotations

from typing import Generator

from fastapi import Request

from python.neo4j_client import Neo4jClient


def get_neo4j_client(request: Request) -> Generator[Neo4jClient, None, None]:
    client: Neo4jClient = request.app.state.neo4j_client
    yield client
