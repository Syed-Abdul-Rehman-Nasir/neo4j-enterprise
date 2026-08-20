"""Pytest fixtures: Neo4j 5.23 Enterprise Testcontainers + seed data."""

from __future__ import annotations

import time
from pathlib import Path

import pytest
from testcontainers.neo4j import Neo4jContainer

from python.neo4j_client import Neo4jClient

ROOT = Path(__file__).resolve().parents[1]
CONSTRAINTS_FILE = ROOT / "cypher" / "00_constraints_indexes.cypher"
SAMPLE_DATA_FILE = ROOT / "cypher" / "01_sample_data.cypher"

# Default Testcontainers Neo4j password
NEO4J_PASSWORD = "testpassword"
NEO4J_USER = "neo4j"


def split_cypher_statements(text: str) -> list[str]:
    """Split a Cypher script into executable statements (skip comment-only blocks)."""
    statements: list[str] = []
    buf: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        buf.append(line)
        if stripped.endswith(";"):
            stmt = "\n".join(buf).strip()
            if stmt.endswith(";"):
                stmt = stmt[:-1].strip()
            if stmt:
                statements.append(stmt)
            buf = []
    trailing = "\n".join(buf).strip()
    if trailing:
        statements.append(trailing)
    return statements


def run_cypher_file(client: Neo4jClient, path: Path) -> None:
    """Execute all statements in a .cypher file (auto-commit for schema DDL)."""
    text = path.read_text(encoding="utf-8")
    with client._driver.session(database=client._database) as session:
        for stmt in split_cypher_statements(text):
            session.run(stmt).consume()


def restore_incidents(client: Neo4jClient) -> None:
    """Re-MERGE sample Incident nodes and AFFECTS relationships."""
    text = SAMPLE_DATA_FILE.read_text(encoding="utf-8")
    incident_start = text.find("// INCIDENTS")
    belongs_start = text.find("// BELONGS_TO")
    affects_start = text.find("// AFFECTS")
    verify_start = text.find("// VERIFICATION")
    chunks: list[str] = []
    if incident_start >= 0 and belongs_start > incident_start:
        chunks.append(text[incident_start:belongs_start])
    if affects_start >= 0:
        end = verify_start if verify_start > affects_start else len(text)
        chunks.append(text[affects_start:end])
    with client._driver.session(database=client._database) as session:
        for chunk in chunks:
            for stmt in split_cypher_statements(chunk):
                session.run(stmt).consume()


def wait_for_bolt(container: Neo4jContainer, timeout_s: float = 120.0) -> None:
    """Poll until Bolt accepts connections (wait_for_port style)."""
    host = container.get_container_host_ip()
    port = int(container.get_exposed_port(7687))
    deadline = time.time() + timeout_s
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            import socket

            with socket.create_connection((host, port), timeout=2.0):
                return
        except OSError as err:
            last_err = err
            time.sleep(1.0)
    raise TimeoutError(f"Bolt port {host}:{port} not ready: {last_err}")


@pytest.fixture(scope="session")
def neo4j_container():
    """Start Neo4j 5.23 Enterprise with APOC; tear down after the session."""
    container = (
        Neo4jContainer("neo4j:5.23-enterprise")
        .with_env("NEO4J_ACCEPT_LICENSE_AGREEMENT", "yes")
        .with_env("NEO4J_PLUGINS", '["apoc"]')
        .with_env("NEO4J_AUTH", f"{NEO4J_USER}/{NEO4J_PASSWORD}")
    )
    container.start()
    wait_for_bolt(container)
    # Extra settle time for plugins / DBMS online
    time.sleep(5)
    yield container
    container.stop()


@pytest.fixture(scope="session")
def neo4j_client(neo4j_container: Neo4jContainer):
    """Session-scoped Neo4jClient bound to the Testcontainers instance."""
    uri = neo4j_container.get_connection_url()
    client = Neo4jClient(
        uri=uri,
        user=NEO4J_USER,
        password=NEO4J_PASSWORD,
        database="neo4j",
        max_pool_size=20,
        connection_timeout=30.0,
    )
    yield client
    client.close()


@pytest.fixture(scope="session", autouse=True)
def load_test_data(neo4j_client: Neo4jClient):
    """Apply constraints/indexes then sample data once per session."""
    run_cypher_file(neo4j_client, CONSTRAINTS_FILE)
    run_cypher_file(neo4j_client, SAMPLE_DATA_FILE)
    yield


@pytest.fixture(scope="function")
def clean_incidents(neo4j_client: Neo4jClient):
    """Yield, then wipe Incidents and restore the sample incident subgraph."""
    yield
    neo4j_client.execute_write("MATCH (i:Incident) DETACH DELETE i", {})
    restore_incidents(neo4j_client)


@pytest.fixture(scope="session")
def project_root() -> Path:
    return ROOT


def load_production_query(cypher_path: Path) -> str:
    """Extract the first non-comment MATCH/RETURN production query from a query file."""
    text = cypher_path.read_text(encoding="utf-8")
    # Take statements; prefer the first that contains $ parameters
    stmts = split_cypher_statements(text)
    for stmt in stmts:
        if "$" in stmt and not stmt.strip().upper().startswith("EXPLAIN"):
            return stmt
    for stmt in stmts:
        if stmt.strip().upper().startswith("MATCH"):
            return stmt
    raise ValueError(f"No production query found in {cypher_path}")
