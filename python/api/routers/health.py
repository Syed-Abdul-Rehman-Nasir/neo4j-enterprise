"""Health endpoint."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request

from python.api.dependencies import get_neo4j_client
from python.api.schemas.common import ComponentHealth, HealthResponse
from python.api.settings import get_settings
from python.api.services.metrics_service import MetricsService
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
def health(request: Request, client: Neo4jClient = Depends(get_neo4j_client)) -> HealthResponse:
    rid = getattr(request.state, "request_id", str(uuid.uuid4()))
    components: list[ComponentHealth] = [
        ComponentHealth(name="api", status="healthy", detail="FastAPI BFF up")
    ]
    try:
        client.verify_connectivity()
        components.append(ComponentHealth(name="neo4j", status="healthy", detail="connected"))
        neo_ok = True
    except Exception as exc:  # noqa: BLE001
        components.append(
            ComponentHealth(name="neo4j", status="critical", detail=str(exc))
        )
        neo_ok = False

    settings = get_settings()
    metrics = MetricsService(settings.prometheus_url)
    if metrics.prometheus_reachable():
        components.append(
            ComponentHealth(name="prometheus", status="healthy", detail=settings.prometheus_url)
        )
        prom_ok = True
    else:
        components.append(
            ComponentHealth(
                name="prometheus",
                status="unknown",
                detail="Prometheus unreachable — metrics will show unknown",
            )
        )
        prom_ok = False

    status = "healthy" if neo_ok else "critical"
    if neo_ok and not prom_ok:
        status = "warning"
    return HealthResponse(status=status, components=components, requestId=rid)  # type: ignore[arg-type]
