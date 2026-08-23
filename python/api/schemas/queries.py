"""Query result and workbench schemas."""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import Field

from .common import CamelModel
from .graph import GraphEdge, GraphNode


class DependencyChainDTO(CamelModel):
    employee: str
    application: str
    applicationId: str
    service: str
    serviceType: str
    database: str
    dbEngine: str
    criticality: float


class ApplicationStatsDTO(CamelModel):
    name: str
    applicationId: str
    tier: int
    uniqueUsers: int
    incidentCount: int


class ImpactedEmployeeDTO(CamelModel):
    name: str
    email: str
    role: str
    department: str
    viaApplication: str
    viaService: str


class IncidentSummaryDTO(CamelModel):
    incidentId: str
    title: str
    severity: str
    status: str
    applicationName: str
    mttrMinutes: Optional[int] = None


class FullDownstreamChainDTO(CamelModel):
    application: str
    appVersion: str
    service: str
    svcType: str
    svcSlaMs: int
    database: str
    dbEngine: str
    dbSizeGb: float
    server: str
    serverRegion: str
    serverOs: str
    criticality: float


class DependencyPathDTO(CamelModel):
    pathNodes: list[str]
    hops: int


class SharedDatabaseEmployeeDTO(CamelModel):
    employee: str
    sharedDatabase: str
    applications: list[str]
    appCount: int


class ApplicationSummaryDTO(CamelModel):
    application: str
    id: str
    owner: str
    tier: int


class ImpactSummary(CamelModel):
    uniqueEmployees: int
    applications: list[str]
    services: list[str]
    departments: list[str]
    pathRowCount: int


class ImpactResponse(CamelModel):
    databaseId: str
    employees: list[ImpactedEmployeeDTO]
    summary: ImpactSummary
    graph: Optional[dict[str, Any]] = None


class PathSegment(CamelModel):
    nodes: list[str]
    nodeNames: list[str]
    hopCount: int
    edges: list[dict[str, Any]] = Field(default_factory=list)


class PathResponse(CamelModel):
    applicationId: str
    databaseId: str
    paths: list[PathSegment]


class QueryParameterSchema(CamelModel):
    name: str
    type: Literal["string", "integer", "datetime", "nullable_datetime"]
    required: bool = True
    default: Any = None
    description: str = ""


class QueryCatalogItem(CamelModel):
    queryId: str
    title: str
    description: str
    cypher: str
    parameters: list[QueryParameterSchema]
    expectedOperators: list[str]
    defaultParams: dict[str, Any]
    presentation: str


class QueryExecutionRequest(CamelModel):
    parameters: dict[str, Any] = Field(default_factory=dict)


class QueryExecutionResponse(CamelModel):
    queryId: str
    columns: list[str]
    rows: list[dict[str, Any]]
    graph: Optional[dict[str, Any]] = None
    executionMs: float
    expectedOperators: list[str]
