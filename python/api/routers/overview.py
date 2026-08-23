"""Overview and meta/catalog routes."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from python.api.dependencies import get_neo4j_client
from python.api.schemas.graph import CatalogItem, MetaModelResponse, OverviewResponse
from python.api.services.graph_service import GraphService
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["overview"])


@router.get("/overview", response_model=OverviewResponse)
def overview(client: Neo4jClient = Depends(get_neo4j_client)) -> OverviewResponse:
    return GraphService(client).get_overview()


@router.get("/meta/model", response_model=MetaModelResponse)
def meta_model(client: Neo4jClient = Depends(get_neo4j_client)) -> MetaModelResponse:
    return GraphService(client).get_meta_model()


@router.get("/catalog/applications", response_model=list[CatalogItem])
def catalog_apps(client: Neo4jClient = Depends(get_neo4j_client)) -> list[CatalogItem]:
    return GraphService(client).catalog_applications()


@router.get("/catalog/databases", response_model=list[CatalogItem])
def catalog_dbs(client: Neo4jClient = Depends(get_neo4j_client)) -> list[CatalogItem]:
    return GraphService(client).catalog_databases()


@router.get("/catalog/employees", response_model=list[CatalogItem])
def catalog_emps(client: Neo4jClient = Depends(get_neo4j_client)) -> list[CatalogItem]:
    return GraphService(client).catalog_employees()
