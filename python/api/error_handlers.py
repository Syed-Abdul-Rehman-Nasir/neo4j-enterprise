"""Map Neo4j client exceptions to HTTP responses."""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from python.exceptions import (
    ConnectionError as Neo4jConnectionError,
    DataError,
    Neo4jClientError,
    QueryError,
    TimeoutError as Neo4jTimeoutError,
)


def _payload(exc: Neo4jClientError, request_id: str) -> dict[str, Any]:
    body = exc.to_dict()
    body["requestId"] = request_id
    return body


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(Neo4jConnectionError)
    async def connection_handler(request: Request, exc: Neo4jConnectionError) -> JSONResponse:
        rid = getattr(request.state, "request_id", str(uuid.uuid4()))
        return JSONResponse(status_code=503, content=_payload(exc, rid))

    @app.exception_handler(Neo4jTimeoutError)
    async def timeout_handler(request: Request, exc: Neo4jTimeoutError) -> JSONResponse:
        rid = getattr(request.state, "request_id", str(uuid.uuid4()))
        return JSONResponse(status_code=504, content=_payload(exc, rid))

    @app.exception_handler(QueryError)
    async def query_handler(request: Request, exc: QueryError) -> JSONResponse:
        rid = getattr(request.state, "request_id", str(uuid.uuid4()))
        return JSONResponse(status_code=400, content=_payload(exc, rid))

    @app.exception_handler(DataError)
    async def data_handler(request: Request, exc: DataError) -> JSONResponse:
        rid = getattr(request.state, "request_id", str(uuid.uuid4()))
        return JSONResponse(status_code=500, content=_payload(exc, rid))

    @app.exception_handler(Neo4jClientError)
    async def client_handler(request: Request, exc: Neo4jClientError) -> JSONResponse:
        rid = getattr(request.state, "request_id", str(uuid.uuid4()))
        return JSONResponse(status_code=500, content=_payload(exc, rid))
