"""Allowlisted Q1–Q9 catalog for the Query Workbench."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Optional

from python.api.schemas.queries import QueryCatalogItem, QueryParameterSchema

REPO_ROOT = Path(__file__).resolve().parents[3]
QUERIES_DIR = REPO_ROOT / "cypher" / "queries"


def _load_production_cypher(filename: str) -> str:
    text = (QUERIES_DIR / filename).read_text(encoding="utf-8")
    # Prefer production block: first MATCH... through ORDER BY / LIMIT before TEST section
    parts = text.split("// --- TEST")
    block = parts[0]
    lines = []
    started = False
    for line in block.splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith(":") or not stripped:
            if started and stripped.startswith("//"):
                continue
            continue
        started = True
        lines.append(line)
    return "\n".join(lines).strip()


_CATALOG: dict[str, QueryCatalogItem] = {
    "q1": QueryCatalogItem(
        queryId="q1",
        title="Department applications",
        description="Applications used by employees in a department with user counts.",
        cypher=_load_production_cypher("q1_finance_apps.cypher"),
        parameters=[
            QueryParameterSchema(
                name="departmentName",
                type="string",
                default="Finance",
                description="Department name",
            )
        ],
        expectedOperators=["NodeIndexSeek", "Expand", "EagerAggregation"],
        defaultParams={"departmentName": "Finance"},
        presentation="bars",
    ),
    "q2": QueryCatalogItem(
        queryId="q2",
        title="Employee dependency chain",
        description="Employee → Application → Service → Database paths.",
        cypher=_load_production_cypher("q2_employee_chain.cypher"),
        parameters=[
            QueryParameterSchema(
                name="employeeId", type="string", default="EMP-001", description="Employee ID"
            )
        ],
        expectedOperators=["NodeIndexSeek", "Expand"],
        defaultParams={"employeeId": "EMP-001"},
        presentation="chain",
    ),
    "q3": QueryCatalogItem(
        queryId="q3",
        title="High-incident applications",
        description="Applications with more than N related incidents.",
        cypher=_load_production_cypher("q3_high_incident_apps.cypher"),
        parameters=[
            QueryParameterSchema(
                name="minIncidents", type="integer", default=0, description="Minimum incident count"
            )
        ],
        expectedOperators=["Expand", "EagerAggregation", "Filter"],
        defaultParams={"minIncidents": 0},
        presentation="severity",
    ),
    "q4": QueryCatalogItem(
        queryId="q4",
        title="Database blast radius",
        description="Employees impacted by a database outage.",
        cypher=_load_production_cypher("q4_db_impact_analysis.cypher"),
        parameters=[
            QueryParameterSchema(
                name="databaseId", type="string", default="DB-001", description="Database ID"
            )
        ],
        expectedOperators=["NodeIndexSeek", "Expand", "Distinct"],
        defaultParams={"databaseId": "DB-001"},
        presentation="blast",
    ),
    "q5": QueryCatalogItem(
        queryId="q5",
        title="Application → database paths",
        description="Bounded DEPENDS_ON paths from an application to a database.",
        cypher=_load_production_cypher("q5_dependency_paths.cypher"),
        parameters=[
            QueryParameterSchema(
                name="applicationId", type="string", default="APP-001", description="Application ID"
            ),
            QueryParameterSchema(
                name="databaseId", type="string", default="DB-001", description="Database ID"
            ),
        ],
        expectedOperators=["NodeIndexSeek", "VarLengthExpand", "Expand"],
        defaultParams={"applicationId": "APP-001", "databaseId": "DB-001"},
        presentation="routes",
    ),
    "q6": QueryCatalogItem(
        queryId="q6",
        title="Top applications by users",
        description="Top N applications by unique employee count.",
        cypher=_load_production_cypher("q6_top_apps_by_users.cypher"),
        parameters=[
            QueryParameterSchema(
                name="limit", type="integer", default=3, description="Result limit"
            )
        ],
        expectedOperators=["EagerAggregation", "Sort", "Limit"],
        defaultParams={"limit": 3},
        presentation="bars",
    ),
    "q7": QueryCatalogItem(
        queryId="q7",
        title="Shared-database exposure",
        description="Employees with multiple apps sharing one database.",
        cypher=_load_production_cypher("q7_shared_db_employees.cypher"),
        parameters=[
            QueryParameterSchema(
                name="minApps", type="integer", default=2, description="Minimum shared apps"
            )
        ],
        expectedOperators=["VarLengthExpand", "EagerAggregation", "Filter"],
        defaultParams={"minApps": 2},
        presentation="matrix",
    ),
    "q8": QueryCatalogItem(
        queryId="q8",
        title="Applications with no incidents",
        description="Applications with no incidents at or before asOf.",
        cypher=_load_production_cypher("q8_no_incidents.cypher"),
        parameters=[
            QueryParameterSchema(
                name="asOf",
                type="nullable_datetime",
                required=False,
                default="2099-12-31T23:59:59",
                description="ISO datetime cutoff or null",
            )
        ],
        expectedOperators=["NodeByLabelScan", "AntiSemiApply", "Sort"],
        defaultParams={"asOf": "2099-12-31T23:59:59"},
        presentation="cards",
    ),
    "q9": QueryCatalogItem(
        queryId="q9",
        title="Full downstream chain",
        description="Application → Service → Database → Server.",
        cypher=_load_production_cypher("q9_full_downstream_chain.cypher"),
        parameters=[
            QueryParameterSchema(
                name="applicationId", type="string", default="APP-001", description="Application ID"
            )
        ],
        expectedOperators=["NodeIndexSeek", "Expand", "Sort"],
        defaultParams={"applicationId": "APP-001"},
        presentation="downstream",
    ),
}


def list_queries() -> list[QueryCatalogItem]:
    return list(_CATALOG.values())


def get_query(query_id: str) -> Optional[QueryCatalogItem]:
    return _CATALOG.get(query_id.lower())


def validate_parameters(query_id: str, params: dict[str, Any]) -> dict[str, Any]:
    item = get_query(query_id)
    if item is None:
        from python.exceptions import QueryError

        raise QueryError(f"Unknown query id: {query_id}", details={"queryId": query_id})
    allowed = {p.name for p in item.parameters}
    unexpected = set(params.keys()) - allowed
    if unexpected:
        from python.exceptions import QueryError

        raise QueryError(
            "Unexpected parameters",
            details={"unexpected": sorted(unexpected), "allowed": sorted(allowed)},
        )
    merged = dict(item.defaultParams)
    merged.update(params)
    for p in item.parameters:
        if p.required and merged.get(p.name) is None and p.type != "nullable_datetime":
            from python.exceptions import QueryError

            raise QueryError(
                f"Missing required parameter: {p.name}",
                details={"parameter": p.name},
            )
        if p.type == "integer" and merged.get(p.name) is not None:
            merged[p.name] = int(merged[p.name])
    return merged
