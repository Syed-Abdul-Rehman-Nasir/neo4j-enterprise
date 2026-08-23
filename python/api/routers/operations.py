"""Operations / monitoring routes."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query

from python.api.dependencies import get_neo4j_client
from python.api.schemas.operations import (
    AlertDefinition,
    MetricSeriesResponse,
    OperationsSummary,
    RunbookStep,
)
from python.api.settings import get_settings
from python.api.services.metrics_service import MetricsService
from python.api.services.operations_service import OperationsService
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["operations"])


@router.get("/operations/summary", response_model=OperationsSummary)
def ops_summary(client: Neo4jClient = Depends(get_neo4j_client)) -> OperationsSummary:
    return OperationsService(client).summary()


@router.get("/operations/metrics", response_model=list[MetricSeriesResponse])
def ops_metrics(
    metrics: Optional[str] = Query(default=None),
    window: str = "15m",
    step: str = "15s",
) -> list[MetricSeriesResponse]:
    settings = get_settings()
    keys = [m.strip() for m in metrics.split(",") if m.strip()] if metrics else []
    return MetricsService(settings.prometheus_url).fetch_metrics(keys, window=window, step=step)


@router.get("/operations/alerts", response_model=list[AlertDefinition])
def ops_alerts(client: Neo4jClient = Depends(get_neo4j_client)) -> list[AlertDefinition]:
    return OperationsService(client).alerts()


@router.get("/operations/runbook", response_model=list[RunbookStep])
def ops_runbook(client: Neo4jClient = Depends(get_neo4j_client)) -> list[RunbookStep]:
    return OperationsService(client).runbook()
