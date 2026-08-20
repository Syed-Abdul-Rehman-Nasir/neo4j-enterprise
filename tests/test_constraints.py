"""Constraint and index enforcement tests against the seeded Enterprise graph."""

from __future__ import annotations

import pytest
from neo4j.exceptions import ClientError, ConstraintError

from python.neo4j_client import Neo4jClient

EXPECTED_CONSTRAINT_COUNT = 12  # 7 uniqueness + 5 existence


def _write_expect_constraint(client: Neo4jClient, query: str, params: dict | None = None) -> None:
    """Run a write that must fail with a constraint violation."""
    params = params or {}
    with client._driver.session(database=client._database) as session:
        with pytest.raises((ConstraintError, ClientError)) as exc_info:
            session.run(query, params).consume()
        err = exc_info.value
        # ConstraintError or ClientError with constraint code
        if isinstance(err, ClientError) and not isinstance(err, ConstraintError):
            code = getattr(err, "code", "") or ""
            msg = str(err).lower()
            assert "constraint" in code.lower() or "constraint" in msg, (
                f"Expected constraint failure, got: {err}"
            )


def test_employee_id_uniqueness(neo4j_client: Neo4jClient):
    _write_expect_constraint(
        neo4j_client,
        """
        CREATE (e:Employee {
          employeeId: 'EMP-001',
          name: 'Duplicate',
          email: 'dup@test.com'
        })
        """,
    )
    rows = neo4j_client.execute_read("MATCH (e:Employee) RETURN count(e) AS c", {})
    assert rows[0]["c"] == 10


def test_employee_email_not_null(neo4j_client: Neo4jClient):
    _write_expect_constraint(
        neo4j_client,
        "CREATE (e:Employee {employeeId: 'EMP-NEW'})",
    )


def test_application_id_uniqueness(neo4j_client: Neo4jClient):
    _write_expect_constraint(
        neo4j_client,
        """
        CREATE (a:Application {
          applicationId: 'APP-001',
          name: 'DupApp'
        })
        """,
    )


def test_incident_severity_not_null(neo4j_client: Neo4jClient, clean_incidents):
    _write_expect_constraint(
        neo4j_client,
        "CREATE (i:Incident {incidentId: 'INC-NEW', title: 'Test'})",
    )


def test_all_constraints_online(neo4j_client: Neo4jClient):
    rows = neo4j_client.execute_read(
        "SHOW CONSTRAINTS YIELD name, state RETURN name, state",
        {},
    )
    assert len(rows) == EXPECTED_CONSTRAINT_COUNT
    for row in rows:
        assert row["state"] == "ONLINE", f"Constraint {row['name']} state={row['state']}"


def test_all_indexes_online(neo4j_client: Neo4jClient):
    rows = neo4j_client.execute_read(
        "SHOW INDEXES YIELD name, state WHERE state <> 'ONLINE' RETURN name, state",
        {},
    )
    assert rows == [] or len(rows) == 0
