"""Graph topology and overview services."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from python.neo4j_client import Neo4jClient
from python.api.schemas.graph import (
    CatalogItem,
    GraphEdge,
    GraphNode,
    GraphResponse,
    LabelDefinition,
    MetaModelResponse,
    NodeDetailResponse,
    OverviewResponse,
    OverviewScenario,
    RelationshipDefinition,
    ScaleTarget,
)
from python.api.services.serialization import (
    LABEL_ID_KEYS,
    node_business_id,
    node_display_name,
    serialize_value,
)

FULL_GRAPH_QUERY = """
MATCH (n)
WITH collect(DISTINCT n) AS nodes
MATCH ()-[r]->()
WITH nodes, collect(DISTINCT r) AS rels
RETURN nodes, rels
"""

NEIGHBORHOOD_QUERY = """
MATCH (n)
WHERE (
  (n:Employee AND n.employeeId = $id) OR
  (n:Department AND n.deptId = $id) OR
  (n:Application AND n.applicationId = $id) OR
  (n:Service AND n.serviceId = $id) OR
  (n:Database AND n.databaseId = $id) OR
  (n:Server AND n.serverId = $id) OR
  (n:Incident AND n.incidentId = $id)
) AND $label IN labels(n)
OPTIONAL MATCH (n)-[r]-(m)
RETURN n, collect(DISTINCT r) AS rels, collect(DISTINCT m) AS neighbors
"""

LABEL_PROPS = {
    "Department": ["deptId", "name", "budget", "headcount", "costCenter"],
    "Employee": ["employeeId", "name", "email", "role", "hireDate"],
    "Application": ["applicationId", "name", "version", "owner", "tier", "description"],
    "Service": ["serviceId", "name", "type", "port", "protocol", "sla_ms"],
    "Database": ["databaseId", "name", "engine", "version", "size_gb", "env", "replication"],
    "Server": ["serverId", "name", "ip", "region", "az", "os", "cpu_cores", "ram_gb"],
    "Incident": ["incidentId", "title", "severity", "status", "ts", "resolvedTs", "mttr_minutes"],
}

REL_DESCRIPTIONS = {
    "BELONGS_TO": "Employee membership in a department",
    "USES": "Employee uses an application",
    "DEPENDS_ON": "Application depends on a service (weighted)",
    "READS_FROM": "Service reads from a database",
    "HOSTED_ON": "Database hosted on a server",
    "AFFECTS": "Incident affects an application",
    "EXTENDS": "Scale-model lineage relationship (0 demo edges)",
}


def _graph_from_nodes_rels(
    nodes_raw: list[Any],
    rels_raw: list[Any],
    *,
    labels_filter: Optional[set[str]] = None,
    rel_filter: Optional[set[str]] = None,
    tier: Optional[int] = None,
    severity: Optional[str] = None,
    environment: Optional[str] = None,
) -> GraphResponse:
    nodes: list[GraphNode] = []
    node_map: dict[str, GraphNode] = {}
    incident_counts: dict[str, int] = {}

    # Pre-count incidents affecting apps from relationships
    for rel in rels_raw:
        if rel is None:
            continue
        if rel.type == "AFFECTS":
            # Incident -> Application
            end = rel.end_node
            end_props = dict(end)
            app_id = end_props.get("applicationId")
            if app_id:
                incident_counts[str(app_id)] = incident_counts.get(str(app_id), 0) + 1

    for n in nodes_raw:
        if n is None:
            continue
        labels = list(n.labels)
        primary = next((l for l in labels if l in LABEL_ID_KEYS), labels[0] if labels else "Employee")
        if labels_filter and primary not in labels_filter:
            continue
        props = {k: serialize_value(v) for k, v in dict(n).items()}
        if tier is not None and primary == "Application" and props.get("tier") != tier:
            continue
        if severity is not None and primary == "Incident" and props.get("severity") != severity:
            continue
        if environment is not None and primary == "Database" and props.get("env") != environment:
            continue
        bid = node_business_id(labels, props, n.element_id)
        gnode = GraphNode(
            id=bid,
            label=primary,  # type: ignore[arg-type]
            displayName=node_display_name(labels, props, bid),
            properties=props,
            incidentCount=incident_counts.get(bid) if primary == "Application" else None,
        )
        nodes.append(gnode)
        node_map[n.element_id] = gnode
        node_map[bid] = gnode

    edges: list[GraphEdge] = []
    for rel in rels_raw:
        if rel is None:
            continue
        rtype = rel.type
        if rel_filter and rtype not in rel_filter:
            continue
        start = rel.start_node
        end = rel.end_node
        start_labels = list(start.labels)
        end_labels = list(end.labels)
        start_props = {k: serialize_value(v) for k, v in dict(start).items()}
        end_props = {k: serialize_value(v) for k, v in dict(end).items()}
        src = node_business_id(start_labels, start_props, start.element_id)
        tgt = node_business_id(end_labels, end_props, end.element_id)
        if labels_filter:
            start_primary = next((l for l in start_labels if l in LABEL_ID_KEYS), None)
            end_primary = next((l for l in end_labels if l in LABEL_ID_KEYS), None)
            if start_primary not in labels_filter or end_primary not in labels_filter:
                continue
        if src not in {n.id for n in nodes} or tgt not in {n.id for n in nodes}:
            # still include if both endpoints present in node_map from unfiltered
            if src not in node_map and tgt not in node_map:
                continue
        edges.append(
            GraphEdge(
                id=f"{src}-{rtype}-{tgt}",
                type=rtype,  # type: ignore[arg-type]
                source=src,
                target=tgt,
                properties={k: serialize_value(v) for k, v in dict(rel).items()},
            )
        )

    counts_by_label: dict[str, int] = {}
    for n in nodes:
        counts_by_label[n.label] = counts_by_label.get(n.label, 0) + 1
    counts_by_rel: dict[str, int] = {}
    for e in edges:
        counts_by_rel[e.type] = counts_by_rel.get(e.type, 0) + 1
    # Always report EXTENDS as 0 in demo
    counts_by_rel.setdefault("EXTENDS", 0)

    return GraphResponse(
        nodes=nodes,
        edges=edges,
        countsByLabel=counts_by_label,
        countsByRelationship=counts_by_rel,
        generatedAt=datetime.now(timezone.utc),
    )


class GraphService:
    def __init__(self, client: Neo4jClient) -> None:
        self._client = client

    def get_full_graph(
        self,
        labels: Optional[list[str]] = None,
        relationships: Optional[list[str]] = None,
        tier: Optional[int] = None,
        severity: Optional[str] = None,
        environment: Optional[str] = None,
    ) -> GraphResponse:
        rows = self._client.execute_read(FULL_GRAPH_QUERY, {})
        if not rows:
            return GraphResponse(
                nodes=[],
                edges=[],
                countsByLabel={},
                countsByRelationship={"EXTENDS": 0},
                generatedAt=datetime.now(timezone.utc),
            )
        record = rows[0]
        return _graph_from_nodes_rels(
            list(record["nodes"]),
            list(record["rels"]),
            labels_filter=set(labels) if labels else None,
            rel_filter=set(relationships) if relationships else None,
            tier=tier,
            severity=severity,
            environment=environment,
        )

    def get_node_detail(self, label: str, node_id: str, depth: int = 1) -> NodeDetailResponse:
        rows = self._client.execute_read(
            NEIGHBORHOOD_QUERY, {"label": label, "id": node_id}
        )
        if not rows or rows[0]["n"] is None:
            from python.exceptions import QueryError

            raise QueryError(
                f"Node {label}/{node_id} not found",
                details={"label": label, "id": node_id},
            )
        rec = rows[0]
        center = rec["n"]
        neighbors = [n for n in rec["neighbors"] if n is not None]
        rels = [r for r in rec["rels"] if r is not None]
        graph = _graph_from_nodes_rels([center, *neighbors], rels)
        center_node = next(n for n in graph.nodes if n.id == node_id or n.label == label)
        # Prefer exact id match
        for n in graph.nodes:
            if n.id == node_id:
                center_node = n
                break
        return NodeDetailResponse(node=center_node, neighborhood=graph)

    def get_overview(self) -> OverviewResponse:
        counts = self._client.execute_read(
            """
            MATCH (n) WITH count(n) AS nodeCount
            MATCH ()-[r]->() WITH nodeCount, count(r) AS relationshipCount
            MATCH (a:Application) WITH nodeCount, relationshipCount, count(a) AS applicationCount
            MATCH (i:Incident) WITH nodeCount, relationshipCount, applicationCount, count(i) AS incidentCount
            MATCH (i2:Incident) WHERE i2.status IN ['open', 'investigating']
            RETURN nodeCount, relationshipCount, applicationCount, incidentCount,
                   count(i2) AS activeIncidentCount
            """,
            {},
        )
        if not counts:
            return OverviewResponse(
                nodeCount=0,
                relationshipCount=0,
                applicationCount=0,
                incidentCount=0,
                activeIncidentCount=0,
                highRiskApplication=None,
                db001Scenario=OverviewScenario(
                    databaseId="DB-001",
                    databaseName="fin-postgres-prod",
                    serviceCount=0,
                    applicationId="APP-001",
                    applicationName="FinanceSuite",
                    employeeCount=0,
                    employeeNames=[],
                ),
                scaleTarget=ScaleTarget(),
                seedLoaded=False,
            )
        c = counts[0]
        risk_rows = self._client.execute_read(
            """
            MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
            WITH a, count(i) AS incidentCount
            ORDER BY incidentCount DESC
            LIMIT 1
            RETURN a.name AS name, a.applicationId AS applicationId, a.tier AS tier, incidentCount
            """,
            {},
        )
        high_risk = None
        if risk_rows:
            r = risk_rows[0]
            high_risk = {
                "name": r["name"],
                "applicationId": r["applicationId"],
                "tier": int(r["tier"]),
                "incidentCount": int(r["incidentCount"]),
            }

        scenario_rows = self._client.execute_read(
            """
            MATCH (db:Database {databaseId: 'DB-001'})<-[:READS_FROM]-(s:Service)
                  <-[:DEPENDS_ON]-(a:Application {applicationId: 'APP-001'})<-[:USES]-(e:Employee)
            RETURN db.name AS databaseName,
                   collect(DISTINCT s.name) AS services,
                   a.name AS applicationName,
                   collect(DISTINCT e.name) AS employees
            """,
            {},
        )
        if scenario_rows:
            s = scenario_rows[0]
            scenario = OverviewScenario(
                databaseId="DB-001",
                databaseName=str(s["databaseName"]),
                serviceCount=len(s["services"] or []),
                applicationId="APP-001",
                applicationName=str(s["applicationName"]),
                employeeCount=len(s["employees"] or []),
                employeeNames=list(s["employees"] or []),
            )
        else:
            scenario = OverviewScenario(
                databaseId="DB-001",
                databaseName="fin-postgres-prod",
                serviceCount=0,
                applicationId="APP-001",
                applicationName="FinanceSuite",
                employeeCount=0,
                employeeNames=[],
            )

        node_count = int(c["nodeCount"])
        return OverviewResponse(
            nodeCount=node_count,
            relationshipCount=int(c["relationshipCount"]),
            applicationCount=int(c["applicationCount"]),
            incidentCount=int(c["incidentCount"]),
            activeIncidentCount=int(c["activeIncidentCount"]),
            highRiskApplication=high_risk,
            db001Scenario=scenario,
            scaleTarget=ScaleTarget(),
            seedLoaded=node_count >= 30,
        )

    def get_meta_model(self) -> MetaModelResponse:
        graph = self.get_full_graph()
        labels = []
        for label, props in LABEL_PROPS.items():
            labels.append(
                LabelDefinition(
                    label=label,  # type: ignore[arg-type]
                    count=graph.countsByLabel.get(label, 0),
                    properties=props,
                    description=f"{label} nodes in the enterprise IT dependency graph",
                )
            )
        rels = []
        for rtype, desc in REL_DESCRIPTIONS.items():
            count = graph.countsByRelationship.get(rtype, 0)
            rels.append(
                RelationshipDefinition(
                    type=rtype,  # type: ignore[arg-type]
                    count=count,
                    demoEdges=count,
                    scaleOnly=(rtype == "EXTENDS"),
                    description=desc,
                )
            )
        return MetaModelResponse(
            labels=labels,
            relationships=rels,
            notes=[
                "EXTENDS is documented for production lineage scale modeling and has zero lab edges.",
                "Demo graph targets 38 nodes and 45 relationships when fully seeded.",
            ],
        )

    def catalog_applications(self) -> list[CatalogItem]:
        rows = self._client.execute_read(
            "MATCH (a:Application) RETURN a.applicationId AS id, a.name AS name, a.tier AS tier ORDER BY id",
            {},
        )
        return [
            CatalogItem(id=str(r["id"]), name=str(r["name"]), extra={"tier": int(r["tier"])})
            for r in rows
        ]

    def catalog_databases(self) -> list[CatalogItem]:
        rows = self._client.execute_read(
            "MATCH (d:Database) RETURN d.databaseId AS id, d.name AS name, d.engine AS engine ORDER BY id",
            {},
        )
        return [
            CatalogItem(id=str(r["id"]), name=str(r["name"]), extra={"engine": str(r["engine"])})
            for r in rows
        ]

    def catalog_employees(self) -> list[CatalogItem]:
        rows = self._client.execute_read(
            "MATCH (e:Employee) RETURN e.employeeId AS id, e.name AS name, e.role AS role ORDER BY id",
            {},
        )
        return [
            CatalogItem(id=str(r["id"]), name=str(r["name"]), extra={"role": str(r["role"])})
            for r in rows
        ]
