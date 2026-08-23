"""FastAPI application entrypoint for the Neo4j Operations Console BFF."""

from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from python.api.error_handlers import register_exception_handlers
from python.api.routers import applications, graph, health, operations, overview, queries
from python.api.settings import get_settings
from python.neo4j_client import Neo4jClient

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    client = Neo4jClient(
        uri=settings.neo4j_uri,
        user=settings.neo4j_username,
        password=settings.neo4j_password,
        database=settings.neo4j_database,
        max_pool_size=settings.neo4j_max_pool_size,
        connection_timeout=settings.neo4j_connection_timeout,
    )
    app.state.neo4j_client = client
    app.state.settings = settings
    logger.info("Neo4j Operations Console API started (read_only=%s)", settings.api_read_only)
    try:
        yield
    finally:
        client.close()
        logger.info("Neo4j Operations Console API shut down")


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Neo4j Enterprise Operations Console API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )
    register_exception_handlers(app)

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        rid = request.headers.get("x-request-id") or str(uuid.uuid4())
        request.state.request_id = rid
        response = await call_next(request)
        response.headers["X-Request-Id"] = rid
        return response

    # Reject non-read methods when API_READ_ONLY (except POST to allowlisted execute)
    @app.middleware("http")
    async def read_only_middleware(request: Request, call_next):
        if settings.api_read_only and request.method not in {"GET", "HEAD", "OPTIONS", "POST"}:
            from fastapi.responses import JSONResponse

            return JSONResponse(
                status_code=405,
                content={
                    "error": "ReadOnlyError",
                    "category": "query",
                    "message": "API is read-only",
                    "details": {},
                    "requestId": getattr(request.state, "request_id", ""),
                },
            )
        if settings.api_read_only and request.method == "POST":
            path = request.url.path
            if not path.endswith("/execute"):
                from fastapi.responses import JSONResponse

                return JSONResponse(
                    status_code=405,
                    content={
                        "error": "ReadOnlyError",
                        "category": "query",
                        "message": "Only allowlisted query execute POST is permitted",
                        "details": {"path": path},
                        "requestId": getattr(request.state, "request_id", ""),
                    },
                )
        return await call_next(request)

    api = FastAPI()  # unused; mount routers on main
    app.include_router(health.router, prefix="/api/v1")
    app.include_router(overview.router, prefix="/api/v1")
    app.include_router(graph.router, prefix="/api/v1")
    app.include_router(applications.router, prefix="/api/v1")
    app.include_router(queries.router, prefix="/api/v1")
    app.include_router(operations.router, prefix="/api/v1")
    return app


app = create_app()
