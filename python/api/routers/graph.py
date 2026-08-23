"""Graph topology routes."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query

from python.api.dependencies import get_neo4j_client
from python.api.schemas.graph import GraphResponse, NodeDetailResponse
from python.api.services.graph_service import GraphService
from python.neo4j_client import Neo4jClient

router = APIRouter(tags=["graph"])


@router.get("/graph", response_model=GraphResponse)
def get_graph(
    labels: Optional[str] = Query(default=None, description="Comma-separated labels"),
    relationships: Optional[str] = Query(default=None),
    tier: Optional[int] = None,
    severity: Optional[str] = None,
    environment: Optional[str] = None,
    client: Neo4jClient = Depends(get_neo4j_client),
) -> GraphResponse:
    label_list = [x.strip() for x in labels.split(",") if x.strip()] if labels else None
    rel_list = (
        [x.strip() for x in relationships.split(",") if x.strip()] if relationships else None
    )
    return GraphService(client).get_full_graph(
        labels=label_list,
        relationships=rel_list,
        tier=tier,
        severity=severity,
        environment=environment,
    )


@router.get("/nodes/{label}/{node_id}", response_model=NodeDetailResponse)
def get_node(
    label: str,
    node_id: str,
    depth: int = 1,
    client: Neo4jClient = Depends(get_neo4j_client),
) -> NodeDetailResponse:
    return GraphService(client).get_node_detail(label, node_id, depth=depth)
