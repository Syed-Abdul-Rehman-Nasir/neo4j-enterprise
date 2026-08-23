"""Graph and catalog schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import Field

from .common import CamelModel, HealthStatus

NodeLabel = Literal[
    "Employee", "Department", "Application", "Service", "Database", "Server", "Incident"
]
RelationshipType = Literal[
    "BELONGS_TO", "USES", "DEPENDS_ON", "READS_FROM", "HOSTED_ON", "AFFECTS", "EXTENDS"
]


class GraphNode(CamelModel):
    id: str
    label: NodeLabel
    displayName: str
    properties: dict[str, Any] = Field(default_factory=dict)
    incidentCount: Optional[int] = None


class GraphEdge(CamelModel):
    id: str
    type: RelationshipType
    source: str
    target: str
    properties: dict[str, Any] = Field(default_factory=dict)


class GraphResponse(CamelModel):
    nodes: list[GraphNode]
    edges: list[GraphEdge]
    countsByLabel: dict[str, int]
    countsByRelationship: dict[str, int]
    generatedAt: datetime


class NodeDetailResponse(CamelModel):
    node: GraphNode
    neighborhood: GraphResponse


class ScaleTarget(CamelModel):
    components: int = 5_000_000
    relationships: int = 100_000_000
    liveBlastRadiusP90Ms: int = 500
    precomputedTierMsMin: int = 1
    precomputedTierMsMax: int = 5


class OverviewScenario(CamelModel):
    databaseId: str
    databaseName: str
    serviceCount: int
    applicationId: str
    applicationName: str
    employeeCount: int
    employeeNames: list[str]


class OverviewResponse(CamelModel):
    nodeCount: int
    relationshipCount: int
    applicationCount: int
    incidentCount: int
    activeIncidentCount: int
    highRiskApplication: Optional[dict[str, Any]] = None
    db001Scenario: OverviewScenario
    scaleTarget: ScaleTarget
    seedLoaded: bool


class ModelProperty(CamelModel):
    name: str
    description: str = ""


class LabelDefinition(CamelModel):
    label: NodeLabel
    count: int
    properties: list[str]
    description: str = ""


class RelationshipDefinition(CamelModel):
    type: RelationshipType
    count: int
    demoEdges: int
    scaleOnly: bool = False
    description: str = ""


class MetaModelResponse(CamelModel):
    labels: list[LabelDefinition]
    relationships: list[RelationshipDefinition]
    notes: list[str] = Field(default_factory=list)


class CatalogItem(CamelModel):
    id: str
    name: str
    extra: dict[str, Any] = Field(default_factory=dict)
