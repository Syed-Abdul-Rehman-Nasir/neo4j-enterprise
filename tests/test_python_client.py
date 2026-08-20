"""Direct tests for the Python Neo4jClient and query helpers."""

from __future__ import annotations

import pytest

from python.exceptions import ConnectionError as Neo4jConnectionError
from python.exceptions import Neo4jClientError
from python.models import DependencyChain
from python.neo4j_client import Neo4jClient
from python.queries import get_dependency_chain
from tests.conftest import NEO4J_PASSWORD, NEO4J_USER


def test_client_connects_successfully(neo4j_client: Neo4jClient):
    neo4j_client.verify_connectivity()


def test_client_raises_connection_error_on_bad_uri():
    with pytest.raises(Neo4jClientError) as exc_info:
        Neo4jClient(
            uri="bolt://127.0.0.1:1",
            user="neo4j",
            password="wrong",
            connection_timeout=2.0,
        )
    assert isinstance(exc_info.value, Neo4jConnectionError)


def test_get_dependency_chain_returns_typed_results(neo4j_client: Neo4jClient):
    result = get_dependency_chain(neo4j_client, "EMP-001")
    assert isinstance(result, list)
    assert len(result) > 0
    assert all(isinstance(row, DependencyChain) for row in result)
    assert result[0].employee == "Alice Mercer"


def test_get_dependency_chain_unknown_employee_returns_empty(neo4j_client: Neo4jClient):
    result = get_dependency_chain(neo4j_client, "EMP-NONEXISTENT")
    assert result == []


def test_session_is_closed_after_context_manager(neo4j_container):
    uri = neo4j_container.get_connection_url()
    with Neo4jClient(uri=uri, user=NEO4J_USER, password=NEO4J_PASSWORD) as client:
        rows = client.execute_read("RETURN 1 AS ok", {})
        assert rows[0]["ok"] == 1
    assert client._closed is True
