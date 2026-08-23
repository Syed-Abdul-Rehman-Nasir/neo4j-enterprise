"""Operations / metrics schemas."""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import Field

from .common import CamelModel, HealthStatus


class MetricPoint(CamelModel):
    timestamp: float
    value: Optional[float] = None


class MetricSeriesResponse(CamelModel):
    metric: str
    unit: str
    status: HealthStatus
    thresholds: dict[str, float] = Field(default_factory=dict)
    points: list[MetricPoint] = Field(default_factory=list)
    source: str
    detail: Optional[str] = None


class ClusterMember(CamelModel):
    role: str
    address: str = ""
    status: str = "unknown"


class OperationsSummary(CamelModel):
    mode: Literal["standalone", "cluster", "unknown"] = "standalone"
    label: str = "Standalone lab"
    productionTargetLabel: str = "Production target: 3 Raft cores + read replicas"
    members: list[ClusterMember] = Field(default_factory=list)
    databaseStatus: str = "unknown"
    constraintCount: int = 0
    indexOnlineCount: int = 0
    replicationLagMs: Optional[float] = None
    health: HealthStatus = "unknown"


class AlertDefinition(CamelModel):
    name: str
    severity: str
    query: str
    message: str
    thresholds: dict[str, float] = Field(default_factory=dict)
    evaluatedStatus: HealthStatus = "unknown"
    tags: list[str] = Field(default_factory=list)


class RunbookStep(CamelModel):
    id: str
    title: str
    summary: str
    commands: list[str] = Field(default_factory=list)
    thresholds: list[str] = Field(default_factory=list)
