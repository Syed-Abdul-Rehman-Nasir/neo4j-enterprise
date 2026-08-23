"""Typed query orchestration for API routes."""

from __future__ import annotations

import time
from typing import Any, Optional

from python import queries as q
from python.api.schemas.queries import (
    ApplicationStatsDTO,
    ApplicationSummaryDTO,
    DependencyChainDTO,
    DependencyPathDTO,
    FullDownstreamChainDTO,
    ImpactedEmployeeDTO,
    ImpactResponse,
    ImpactSummary,
    IncidentSummaryDTO,
    PathResponse,
    PathSegment,
    QueryExecutionResponse,
    SharedDatabaseEmployeeDTO,
)
from python.api.services import query_catalog
from python.api.services.serialization import record_to_dict, serialize_value
from python.neo4j_client import Neo4jClient


def _stats(m) -> ApplicationStatsDTO:
    return ApplicationStatsDTO(
        name=m.name,
        applicationId=m.applicationId,
        tier=m.tier,
        uniqueUsers=m.uniqueUsers,
        incidentCount=m.incidentCount,
    )


class QueryService:
    def __init__(self, client: Neo4jClient) -> None:
        self._client = client

    def department_applications(self, department_name: str) -> list[ApplicationStatsDTO]:
        return [_stats(m) for m in q.get_finance_applications(self._client, department_name)]

    def dependency_chain(self, employee_id: str) -> list[DependencyChainDTO]:
        return [
            DependencyChainDTO(**m.to_dict())
            for m in q.get_dependency_chain(self._client, employee_id)
        ]

    def high_incidents(self, min_incidents: int = 3) -> list[dict[str, Any]]:
        # Enrich with titles/severities from Cypher file shape
        cypher = """
        MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
        OPTIONAL MATCH (a)<-[:USES]-(e:Employee)
        WITH a,
             count(DISTINCT i) AS incidentCount,
             count(DISTINCT e) AS uniqueUsers,
             collect(i.title) AS incidentTitles,
             collect(i.severity) AS severities
        WHERE incidentCount > $minIncidents
        RETURN a.name AS name,
               a.applicationId AS applicationId,
               a.tier AS tier,
               uniqueUsers,
               incidentCount,
               incidentTitles,
               severities
        ORDER BY incidentCount DESC
        """
        rows = self._client.execute_read(cypher, {"minIncidents": min_incidents})
        return [record_to_dict(r) for r in rows]

    def database_impact(self, database_id: str) -> ImpactResponse:
        employees = [
            ImpactedEmployeeDTO(**m.to_dict())
            for m in q.get_impacted_employees(self._client, database_id)
        ]
        apps = sorted({e.viaApplication for e in employees})
        services = sorted({e.viaService for e in employees})
        departments = sorted({e.department for e in employees})
        unique = {e.name for e in employees}
        return ImpactResponse(
            databaseId=database_id,
            employees=employees,
            summary=ImpactSummary(
                uniqueEmployees=len(unique),
                applications=apps,
                services=services,
                departments=departments,
                pathRowCount=len(employees),
            ),
        )

    def application_paths(self, application_id: str, database_id: str) -> PathResponse:
        paths = q.get_dependency_paths(self._client, application_id, database_id)
        return PathResponse(
            applicationId=application_id,
            databaseId=database_id,
            paths=[
                PathSegment(
                    nodes=p.path_nodes,
                    nodeNames=p.path_nodes,
                    hopCount=p.hops,
                )
                for p in paths
            ],
        )

    def top_by_users(self, limit: int = 3) -> list[ApplicationStatsDTO]:
        return [_stats(m) for m in q.get_top_applications_by_users(self._client, limit)]

    def shared_database_exposure(self, min_apps: int = 2) -> list[SharedDatabaseEmployeeDTO]:
        return [
            SharedDatabaseEmployeeDTO(
                employee=m.employee,
                sharedDatabase=m.shared_database,
                applications=m.applications,
                appCount=m.app_count,
            )
            for m in q.get_shared_database_employees(self._client, min_apps)
        ]

    def no_incidents(self, as_of: Optional[str] = None) -> list[ApplicationSummaryDTO]:
        return [
            ApplicationSummaryDTO(**m.to_dict())
            for m in q.get_applications_with_no_incidents(self._client, as_of)
        ]

    def downstream(self, application_id: str) -> list[FullDownstreamChainDTO]:
        return [
            FullDownstreamChainDTO(**m.to_dict())
            for m in q.get_application_full_chain(self._client, application_id)
        ]

    def incidents(
        self,
        application_id: Optional[str] = None,
        severity: Optional[str] = None,
        status: Optional[str] = None,
    ) -> list[IncidentSummaryDTO]:
        cypher = """
        MATCH (i:Incident)-[:AFFECTS]->(a:Application)
        WHERE ($applicationId IS NULL OR a.applicationId = $applicationId)
          AND ($severity IS NULL OR i.severity = $severity)
          AND ($status IS NULL OR i.status = $status)
        RETURN i.incidentId AS incidentId,
               i.title AS title,
               i.severity AS severity,
               i.status AS status,
               a.name AS applicationName,
               i.mttr_minutes AS mttrMinutes,
               i.ts AS ts
        ORDER BY i.ts DESC
        """
        rows = self._client.execute_read(
            cypher,
            {
                "applicationId": application_id,
                "severity": severity,
                "status": status,
            },
        )
        out: list[IncidentSummaryDTO] = []
        for r in rows:
            mttr = r.get("mttrMinutes")
            out.append(
                IncidentSummaryDTO(
                    incidentId=str(r["incidentId"]),
                    title=str(r["title"]),
                    severity=str(r["severity"]),
                    status=str(r["status"]),
                    applicationName=str(r["applicationName"]),
                    mttrMinutes=int(mttr) if mttr is not None else None,
                )
            )
        return out

    def execute(self, query_id: str, parameters: dict[str, Any]) -> QueryExecutionResponse:
        item = query_catalog.get_query(query_id)
        if item is None:
            from python.exceptions import QueryError

            raise QueryError(f"Unknown query id: {query_id}", details={"queryId": query_id})
        params = query_catalog.validate_parameters(query_id, parameters)
        started = time.perf_counter()
        rows_raw = self._client.execute_read(item.cypher, params)
        elapsed = (time.perf_counter() - started) * 1000.0
        rows = [record_to_dict(r) for r in rows_raw]
        columns = list(rows[0].keys()) if rows else []
        return QueryExecutionResponse(
            queryId=query_id.lower(),
            columns=columns,
            rows=rows,
            executionMs=round(elapsed, 2),
            expectedOperators=item.expectedOperators,
        )
