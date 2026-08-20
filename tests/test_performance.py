"""EXPLAIN-based tests that lookups use indexes (NodeIndexSeek)."""

from __future__ import annotations

from typing import Any

from python.neo4j_client import Neo4jClient


def _plan_operators(plan: Any) -> list[str]:
    """Flatten operator names from a Neo4j SUMMARY plan tree."""
    names: list[str] = []
    if plan is None:
        return names
    op = getattr(plan, "operator_type", None) or getattr(plan, "name", None)
    if op:
        names.append(str(op))
    children = getattr(plan, "children", None) or []
    for child in children:
        names.extend(_plan_operators(child))
    # Also support dict-like plans
    if isinstance(plan, dict):
        names.append(str(plan.get("operatorType") or plan.get("name") or ""))
        for child in plan.get("children") or []:
            names.extend(_plan_operators(child))
    return [n for n in names if n]


def _explain_ops(client: Neo4jClient, cypher: str) -> list[str]:
    with client._driver.session(database=client._database) as session:
        result = session.run(f"EXPLAIN {cypher}")
        summary = result.consume()
        plan = summary.plan
        ops = _plan_operators(plan)
        # Fallback: stringify entire summary if tree empty
        if not ops:
            text = str(summary)
            return [text]
        return ops


def _assert_index_seek(ops: list[str]) -> None:
    joined = " ".join(ops)
    has_seek = (
        "NodeIndexSeek" in joined
        or "NodeUniqueIndexSeek" in joined
        or "NodeIndexSeekByRange" in joined
    )
    assert has_seek, f"Expected index seek in plan, got: {joined}"
    assert "NodeByLabelScan" not in joined, f"Unexpected NodeByLabelScan in plan: {joined}"


def test_employee_lookup_uses_index(neo4j_client: Neo4jClient):
    ops = _explain_ops(
        neo4j_client,
        "MATCH (e:Employee {employeeId: 'EMP-001'}) RETURN e",
    )
    _assert_index_seek(ops)
    assert "NodeByLabelScan" not in " ".join(ops)


def test_application_lookup_uses_index(neo4j_client: Neo4jClient):
    ops = _explain_ops(
        neo4j_client,
        "MATCH (a:Application {applicationId: 'APP-001'}) RETURN a",
    )
    _assert_index_seek(ops)
    assert "NodeByLabelScan" not in " ".join(ops)


def test_incident_status_uses_index(neo4j_client: Neo4jClient):
    ops = _explain_ops(
        neo4j_client,
        "MATCH (i:Incident {status: 'open'}) RETURN i",
    )
    _assert_index_seek(ops)
