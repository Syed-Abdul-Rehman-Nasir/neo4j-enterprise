"""Typed query helpers for the Enterprise IT dependency graph.

All Cypher lives in module-level constants and uses ``$parameters`` only
(never f-strings or ``str.format``).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Optional

from .exceptions import DataError, Neo4jClientError, QueryError
from .models import (
    ApplicationStats,
    ApplicationSummary,
    DependencyChain,
    DependencyPath,
    FullDownstreamChain,
    ImpactedEmployee,
    IncidentSummary,
    SharedDatabaseEmployee,
)

if TYPE_CHECKING:
    from .neo4j_client import Neo4jClient


# ---------------------------------------------------------------------------
# Cypher constants
# ---------------------------------------------------------------------------

QUERY_GET_DEPENDENCY_CHAIN = """
MATCH (e:Employee {employeeId: $employeeId})
MATCH (e)-[:USES]->(a:Application)-[dep:DEPENDS_ON]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name AS employee,
       a.name AS application,
       a.applicationId AS applicationId,
       s.name AS service,
       s.type AS serviceType,
       db.name AS database,
       db.engine AS dbEngine,
       dep.weight AS criticality
ORDER BY application, service
"""

QUERY_GET_FINANCE_APPLICATIONS = """
MATCH (d:Department {name: $departmentName})
MATCH (e:Employee)-[:BELONGS_TO]->(d)
MATCH (e)-[:USES]->(a:Application)
OPTIONAL MATCH (a)<-[:AFFECTS]-(i:Incident)
WITH a, count(DISTINCT e) AS uniqueUsers, count(DISTINCT i) AS incidentCount
RETURN a.name AS name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       uniqueUsers,
       incidentCount
ORDER BY uniqueUsers DESC
"""

QUERY_GET_HIGH_INCIDENT_APPLICATIONS = """
MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
OPTIONAL MATCH (a)<-[:USES]-(e:Employee)
WITH a,
     count(DISTINCT i) AS incidentCount,
     count(DISTINCT e) AS uniqueUsers
WHERE incidentCount > $minIncidents
RETURN a.name AS name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       uniqueUsers,
       incidentCount
ORDER BY incidentCount DESC
"""

QUERY_GET_IMPACTED_EMPLOYEES = """
MATCH (db:Database {databaseId: $databaseId})<-[:READS_FROM]-(s:Service)
      <-[:DEPENDS_ON]-(a:Application)<-[:USES]-(e:Employee)
MATCH (e)-[:BELONGS_TO]->(d:Department)
RETURN DISTINCT e.name AS name,
       e.email AS email,
       e.role AS role,
       d.name AS department,
       a.name AS viaApplication,
       s.name AS viaService
ORDER BY name
"""

QUERY_GET_APPLICATION_FULL_CHAIN = """
MATCH (a:Application {applicationId: $applicationId})-[r1:DEPENDS_ON]->(s:Service)
      -[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
RETURN a.name AS application,
       a.version AS appVersion,
       s.name AS service,
       s.type AS svcType,
       s.sla_ms AS svcSlaMs,
       db.name AS database,
       db.engine AS dbEngine,
       db.size_gb AS dbSizeGb,
       srv.name AS server,
       srv.region AS serverRegion,
       srv.os AS serverOs,
       r1.weight AS criticality
ORDER BY criticality DESC
"""

QUERY_GET_DEPENDENCY_PATHS = """
MATCH (a:Application {applicationId: $applicationId})
MATCH (db:Database {databaseId: $databaseId})
MATCH path = (a)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db)
RETURN [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)] AS path_nodes,
       length(path) AS hops
ORDER BY hops ASC
"""

QUERY_GET_TOP_APPLICATIONS_BY_USERS = """
MATCH (a:Application)<-[:USES]-(e:Employee)
WITH a, count(DISTINCT e) AS uniqueUsers
RETURN a.name AS name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       uniqueUsers,
       0 AS incidentCount
ORDER BY uniqueUsers DESC, applicationId ASC
LIMIT $limit
"""

QUERY_GET_SHARED_DATABASE_EMPLOYEES = """
MATCH (e:Employee)-[:USES]->(a:Application)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db:Database)
WITH e, db, collect(DISTINCT a) AS apps
WHERE size(apps) >= $minApps
RETURN e.name AS employee,
       db.name AS shared_database,
       [x IN apps | x.name] AS applications,
       size(apps) AS app_count
ORDER BY app_count DESC
"""

QUERY_GET_APPLICATIONS_WITH_NO_INCIDENTS = """
MATCH (a:Application)
WHERE NOT EXISTS {
  MATCH (i:Incident)-[:AFFECTS]->(a)
  WHERE $asOf IS NULL OR i.ts <= datetime($asOf)
}
RETURN a.name AS application,
       a.applicationId AS id,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC
"""

QUERY_GET_OPEN_INCIDENTS = """
MATCH (i:Incident)-[:AFFECTS]->(a:Application)
WHERE i.status = $status
RETURN i.incidentId AS incidentId,
       i.title AS title,
       i.severity AS severity,
       i.status AS status,
       a.name AS applicationName,
       i.mttr_minutes AS mttr_minutes
ORDER BY i.severity ASC, i.ts ASC
"""


# ---------------------------------------------------------------------------
# Query functions
# ---------------------------------------------------------------------------

def get_dependency_chain(client: "Neo4jClient", employee_id: str) -> list[DependencyChain]:
    """Return Employee → Application → Service → Database rows for one employee.

    Parameters
    ----------
    client:
        Connected :class:`~python.neo4j_client.Neo4jClient`.
    employee_id:
        Unique ``Employee.employeeId`` (e.g. ``EMP-001``).

    Returns
    -------
    list[DependencyChain]
        One immutable row per app/service/database path, ordered by application
        and service name.

    Raises
    ------
    ConnectionError, QueryError, TimeoutError, DataError
        Propagated from the client / record parsing layer.
    """
    records = client.execute_read(
        QUERY_GET_DEPENDENCY_CHAIN, {"employeeId": employee_id}
    )
    try:
        return [DependencyChain.from_record(r) for r in records]
    except DataError:
        raise
    except Neo4jClientError:
        raise
    except Exception as err:  # noqa: BLE001
        raise QueryError(
            "Failed building DependencyChain results",
            details={"cause": str(err)},
        ) from err


def get_finance_applications(
    client: "Neo4jClient", department_name: str = "Finance"
) -> list[ApplicationStats]:
    """Return applications used by employees in a department with usage stats.

    Parameters
    ----------
    client:
        Connected Neo4j client.
    department_name:
        Department ``name`` property (default ``Finance``).

    Returns
    -------
    list[ApplicationStats]
        Applications with ``uniqueUsers`` and ``incidentCount``, ordered by
        unique user count descending.

    Raises
    ------
    ConnectionError, QueryError, TimeoutError, DataError
    """
    records = client.execute_read(
        QUERY_GET_FINANCE_APPLICATIONS, {"departmentName": department_name}
    )
    return [ApplicationStats.from_record(r) for r in records]


def get_high_incident_applications(
    client: "Neo4jClient", min_incidents: int = 3
) -> list[ApplicationStats]:
    """Return applications whose incident count exceeds ``min_incidents``.

    Parameters
    ----------
    client:
        Connected Neo4j client.
    min_incidents:
        Exclusive lower bound on distinct incident count (default ``3``).

    Returns
    -------
    list[ApplicationStats]
        Ordered by ``incidentCount`` descending.

    Raises
    ------
    ConnectionError, QueryError, TimeoutError, DataError
    """
    records = client.execute_read(
        QUERY_GET_HIGH_INCIDENT_APPLICATIONS, {"minIncidents": min_incidents}
    )
    return [ApplicationStats.from_record(r) for r in records]


def get_impacted_employees(
    client: "Neo4jClient", database_id: str
) -> list[ImpactedEmployee]:
    """Return employees in the blast radius of a database outage.

    Traverses Database ← Service ← Application ← Employee and attaches
    department membership.

    Parameters
    ----------
    client:
        Connected Neo4j client.
    database_id:
        Unique ``Database.databaseId`` (e.g. ``DB-001``).

    Returns
    -------
    list[ImpactedEmployee]
        Distinct employee/path rows ordered by name.

    Raises
    ------
    ConnectionError, QueryError, TimeoutError, DataError
    """
    records = client.execute_read(
        QUERY_GET_IMPACTED_EMPLOYEES, {"databaseId": database_id}
    )
    return [ImpactedEmployee.from_record(r) for r in records]


def get_application_full_chain(
    client: "Neo4jClient", application_id: str
) -> list[FullDownstreamChain]:
    """Return Application → Service → Database → Server for one application.

    Parameters
    ----------
    client:
        Connected Neo4j client.
    application_id:
        Unique ``Application.applicationId`` (e.g. ``APP-001``).

    Returns
    -------
    list[FullDownstreamChain]
        Ordered by dependency ``criticality`` (weight) descending.

    Raises
    ------
    ConnectionError, QueryError, TimeoutError, DataError
    """
    records = client.execute_read(
        QUERY_GET_APPLICATION_FULL_CHAIN, {"applicationId": application_id}
    )
    return [FullDownstreamChain.from_record(r) for r in records]


def get_dependency_paths(
    client: "Neo4jClient", application_id: str, database_id: str
) -> list[DependencyPath]:
    """Return bounded dependency paths from an application to a database (Q5).

    Parameters
    ----------
    client:
        Connected Neo4j client.
    application_id:
        Unique ``Application.applicationId``.
    database_id:
        Unique ``Database.databaseId``.

    Returns
    -------
    list[DependencyPath]
        Paths ordered by hop count ascending (shortest first).
    """
    records = client.execute_read(
        QUERY_GET_DEPENDENCY_PATHS,
        {"applicationId": application_id, "databaseId": database_id},
    )
    return [DependencyPath.from_record(r) for r in records]


def get_top_applications_by_users(
    client: "Neo4jClient", limit: int = 3
) -> list[ApplicationStats]:
    """Return the top N applications by unique employee count (Q6).

    Parameters
    ----------
    client:
        Connected Neo4j client.
    limit:
        Maximum number of applications to return (default ``3``).

    Returns
    -------
    list[ApplicationStats]
        Ordered by ``uniqueUsers`` descending, then ``applicationId`` ascending.
        ``incidentCount`` is ``0`` (not computed by this query).
    """
    records = client.execute_read(
        QUERY_GET_TOP_APPLICATIONS_BY_USERS, {"limit": limit}
    )
    return [ApplicationStats.from_record(r) for r in records]


def get_shared_database_employees(
    client: "Neo4jClient", min_apps: int = 2
) -> list[SharedDatabaseEmployee]:
    """Return employees with multiple apps sharing one database (Q7).

    Parameters
    ----------
    client:
        Connected Neo4j client.
    min_apps:
        Minimum distinct applications per (employee, database) pair.

    Returns
    -------
    list[SharedDatabaseEmployee]
        Ordered by ``app_count`` descending.
    """
    records = client.execute_read(
        QUERY_GET_SHARED_DATABASE_EMPLOYEES, {"minApps": min_apps}
    )
    return [SharedDatabaseEmployee.from_record(r) for r in records]


def get_applications_with_no_incidents(
    client: "Neo4jClient", as_of: Optional[str] = None
) -> list[ApplicationSummary]:
    """Return applications with no incidents at or before ``as_of`` (Q8).

    Parameters
    ----------
    client:
        Connected Neo4j client.
    as_of:
        ISO datetime string cutoff, or ``None`` to treat any incident as present.

    Returns
    -------
    list[ApplicationSummary]
        Ordered by tier ascending, then application name.
    """
    records = client.execute_read(
        QUERY_GET_APPLICATIONS_WITH_NO_INCIDENTS, {"asOf": as_of}
    )
    return [ApplicationSummary.from_record(r) for r in records]


def get_open_incidents(
    client: "Neo4jClient", status: str = "open"
) -> list[IncidentSummary]:
    """Return incidents matching ``status`` with their affected application.

    Parameters
    ----------
    client:
        Connected Neo4j client.
    status:
        Incident ``status`` property filter (default ``open``).

    Returns
    -------
    list[IncidentSummary]
        Ordered by severity, then incident timestamp.
    """
    records = client.execute_read(QUERY_GET_OPEN_INCIDENTS, {"status": status})
    return [IncidentSummary.from_record(r) for r in records]
