"""API unit tests that do not require a live Neo4j (catalog / validation)."""

from __future__ import annotations

import pytest

from python.api.services import query_catalog
from python.exceptions import QueryError


def test_catalog_has_nine_queries():
    items = query_catalog.list_queries()
    assert len(items) == 9
    ids = {i.queryId for i in items}
    assert ids == {f"q{i}" for i in range(1, 10)}


def test_validate_rejects_unknown_query():
    with pytest.raises(QueryError):
        query_catalog.validate_parameters("q99", {})


def test_validate_rejects_extra_params():
    with pytest.raises(QueryError):
        query_catalog.validate_parameters("q4", {"databaseId": "DB-001", "extra": 1})


def test_validate_q4_defaults():
    params = query_catalog.validate_parameters("q4", {})
    assert params["databaseId"] == "DB-001"


def test_cypher_loaded_for_q4():
    item = query_catalog.get_query("q4")
    assert item is not None
    assert "$databaseId" in item.cypher
    assert "MATCH" in item.cypher
