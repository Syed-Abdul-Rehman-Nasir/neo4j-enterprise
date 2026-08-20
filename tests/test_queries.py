"""Query correctness tests against the known sample dataset (q1–q9)."""

from __future__ import annotations

from pathlib import Path

import pytest

from python.neo4j_client import Neo4jClient
from tests.conftest import load_production_query

QUERIES = Path(__file__).resolve().parents[1] / "cypher" / "queries"


def _run(client: Neo4jClient, filename: str, params: dict) -> list:
    query = load_production_query(QUERIES / filename)
    return client.execute_read(query, params)


def test_q1_finance_apps_returns_correct_apps(neo4j_client: Neo4jClient):
    rows = _run(neo4j_client, "q1_finance_apps.cypher", {"departmentName": "Finance"})
    by_id = {r["applicationId"]: r for r in rows}

    assert "APP-001" in by_id
    assert "APP-004" in by_id
    assert "APP-002" not in by_id
    assert by_id["APP-001"]["user_count"] == 4


def test_q2_employee_chain_emp001(neo4j_client: Neo4jClient):
    rows = _run(neo4j_client, "q2_employee_chain.cypher", {"employeeId": "EMP-001"})
    triples = {
        (r["application"], r["service"], r["database"]) for r in rows
    }
    assert all(r["applicationId"].startswith("APP-") for r in rows)

    assert ("FinanceSuite", "auth-service", "fin-postgres-prod") in triples
    assert ("FinanceSuite", "reporting-svc", "fin-postgres-prod") in triples
    assert ("DataLakeDash", "data-ingest", "datalake-pg-prod") in triples


def test_q3_high_incident_apps(neo4j_client: Neo4jClient):
    rows = _run(neo4j_client, "q3_high_incident_apps.cypher", {"minIncidents": 3})
    ids = {r["applicationId"] for r in rows}
    assert ids == {"APP-001"}
    assert "APP-002" not in ids
    assert rows[0]["incident_count"] == 6

    rows_lo = _run(neo4j_client, "q3_high_incident_apps.cypher", {"minIncidents": 0})
    ids_lo = {r["applicationId"] for r in rows_lo}
    assert "APP-001" in ids_lo
    assert "APP-002" in ids_lo
    assert "APP-004" in ids_lo


def test_q4_impacted_employees_for_db001(neo4j_client: Neo4jClient):
    rows = _run(neo4j_client, "q4_db_impact_analysis.cypher", {"databaseId": "DB-001"})
    names = [r["impacted_employee"] for r in rows]
    assert "Alice Mercer" in names
    assert "Bob Tanaka" in names
    assert "Eva Petrov" in names
    assert "Grace Kim" in names
    assert "Carol Davis" not in names

    keys = [
        (r["impacted_employee"], r["via_application"], r["via_service"]) for r in rows
    ]
    assert len(keys) == len(set(keys))


def test_q5_dependency_paths(neo4j_client: Neo4jClient):
    rows = _run(
        neo4j_client,
        "q5_dependency_paths.cypher",
        {"applicationId": "APP-001", "databaseId": "DB-001"},
    )
    assert len(rows) >= 2
    for r in rows:
        assert r["hops"] == 2
        assert isinstance(r["path_nodes"], list)
        assert len(r["path_nodes"]) >= 2


def test_q6_top_apps(neo4j_client: Neo4jClient):
    rows = _run(neo4j_client, "q6_top_apps_by_users.cypher", {"limit": 3})
    assert len(rows) == 3
    assert rows[0]["applicationId"] == "APP-001"
    assert rows[0]["unique_users"] == 4


def test_q7_shared_db_employees(neo4j_client: Neo4jClient):
    """Employees with ≥2 apps sharing one DB.

    Seed topology: EMP-001 uses APP-001→DB-001 and APP-004→DB-003 (different DBs),
    so EMP-001 is not expected. Assert query runs and respects minApps filter.
    """
    rows = _run(neo4j_client, "q7_shared_db_employees.cypher", {"minApps": 2})
    names = {r["employee"] for r in rows}
    assert "Alice Mercer" not in names
    for r in rows:
        assert r["app_count"] >= 2


def test_q8_no_incidents(neo4j_client: Neo4jClient):
    rows = _run(
        neo4j_client,
        "q8_no_incidents.cypher",
        {"asOf": "2099-12-31T23:59:59"},
    )
    ids = {r["id"] for r in rows}
    assert "APP-003" in ids
    assert "APP-005" in ids
    assert "APP-001" not in ids


def test_q9_full_chain_app001(neo4j_client: Neo4jClient):
    rows = _run(
        neo4j_client, "q9_full_downstream_chain.cypher", {"applicationId": "APP-001"}
    )
    servers = {r["server"] for r in rows}
    services = {r["service"] for r in rows}
    by_svc = {r["service"]: r["dependency_criticality"] for r in rows}

    assert "db-primary-east" in servers
    assert "auth-service" in services
    assert "reporting-svc" in services
    assert by_svc["auth-service"] == pytest.approx(1.0)
    assert by_svc["reporting-svc"] == pytest.approx(0.8)
