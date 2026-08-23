"""Domain query routes wrapping Q1–Q9 helpers."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, Query

from python.api.dependencies import get_neo4j_client
from python.api.schemas.queries import (
    ApplicationStatsDTO,
    ApplicationSummaryDTO,
    DependencyChainDTO,
    FullDownstreamChainDTO,
    ImpactResponse,
    IncidentSummaryDTO,
    PathResponse,
    SharedDatabaseEmployeeDTO,
)
from python.api.services.query_service import QueryService
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["domain"])


@router.get("/departments/{department_name}/applications", response_model=list[ApplicationStatsDTO])
def dept_apps(
    department_name: str, client: Neo4jClient = Depends(get_neo4j_client)
) -> list[ApplicationStatsDTO]:
    return QueryService(client).department_applications(department_name)


@router.get("/employees/{employee_id}/dependency-chain", response_model=list[DependencyChainDTO])
def emp_chain(
    employee_id: str, client: Neo4jClient = Depends(get_neo4j_client)
) -> list[DependencyChainDTO]:
    return QueryService(client).dependency_chain(employee_id)


@router.get("/applications/high-incidents")
def high_incidents(
    minIncidents: int = Query(default=3, alias="minIncidents"),
    client: Neo4jClient = Depends(get_neo4j_client),
) -> list[dict[str, Any]]:
    return QueryService(client).high_incidents(minIncidents)


@router.get("/databases/{database_id}/impact", response_model=ImpactResponse)
def db_impact(
    database_id: str, client: Neo4jClient = Depends(get_neo4j_client)
) -> ImpactResponse:
    return QueryService(client).database_impact(database_id)


@router.get(
    "/applications/{application_id}/paths/{database_id}", response_model=PathResponse
)
def app_paths(
    application_id: str,
    database_id: str,
    client: Neo4jClient = Depends(get_neo4j_client),
) -> PathResponse:
    return QueryService(client).application_paths(application_id, database_id)


@router.get("/applications/top-by-users", response_model=list[ApplicationStatsDTO])
def top_users(
    limit: int = 3, client: Neo4jClient = Depends(get_neo4j_client)
) -> list[ApplicationStatsDTO]:
    return QueryService(client).top_by_users(limit)


@router.get("/exposure/shared-database", response_model=list[SharedDatabaseEmployeeDTO])
def shared_db(
    minApps: int = Query(default=2, alias="minApps"),
    client: Neo4jClient = Depends(get_neo4j_client),
) -> list[SharedDatabaseEmployeeDTO]:
    return QueryService(client).shared_database_exposure(minApps)


@router.get("/applications/no-incidents", response_model=list[ApplicationSummaryDTO])
def no_incidents(
    asOf: Optional[str] = Query(default="2099-12-31T23:59:59", alias="asOf"),
    client: Neo4jClient = Depends(get_neo4j_client),
) -> list[ApplicationSummaryDTO]:
    return QueryService(client).no_incidents(asOf)


@router.get(
    "/applications/{application_id}/downstream",
    response_model=list[FullDownstreamChainDTO],
)
def downstream(
    application_id: str, client: Neo4jClient = Depends(get_neo4j_client)
) -> list[FullDownstreamChainDTO]:
    return QueryService(client).downstream(application_id)


@router.get("/incidents", response_model=list[IncidentSummaryDTO])
def incidents(
    applicationId: Optional[str] = Query(default=None, alias="applicationId"),
    severity: Optional[str] = None,
    status: Optional[str] = None,
    client: Neo4jClient = Depends(get_neo4j_client),
) -> list[IncidentSummaryDTO]:
    return QueryService(client).incidents(applicationId, severity, status)
