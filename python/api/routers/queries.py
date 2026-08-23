"""Query workbench routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from python.api.dependencies import get_neo4j_client
from python.api.schemas.queries import (
    QueryCatalogItem,
    QueryExecutionRequest,
    QueryExecutionResponse,
)
from python.api.services import query_catalog
from python.api.services.query_service import QueryService
from python.exceptions import QueryError
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["queries"])


@router.get("/queries", response_model=list[QueryCatalogItem])
def list_queries() -> list[QueryCatalogItem]:
    return query_catalog.list_queries()


@router.get("/queries/{query_id}", response_model=QueryCatalogItem)
def get_query(query_id: str) -> QueryCatalogItem:
    item = query_catalog.get_query(query_id)
    if item is None:
        raise QueryError(f"Unknown query id: {query_id}", details={"queryId": query_id})
    return item


@router.post("/queries/{query_id}/execute", response_model=QueryExecutionResponse)
def execute_query(
    query_id: str,
    body: QueryExecutionRequest,
    client: Neo4jClient = Depends(get_neo4j_client),
) -> QueryExecutionResponse:
    return QueryService(client).execute(query_id, body.parameters)
