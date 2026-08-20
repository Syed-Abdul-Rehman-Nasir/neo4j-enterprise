"""Production Neo4j driver wrapper with retry-aware read/write transactions.

Prefer using this client as a context manager::

    with Neo4jClient(uri, user, password) as client:
        rows = client.execute_read(QUERY, {"id": "EMP-001"})

Call :meth:`close` (or rely on ``__exit__`` / ``atexit``) so the driver pool
is shut down cleanly.
"""

from __future__ import annotations

import atexit
import logging
import time
from types import TracebackType
from typing import Any, Optional, Type

from neo4j import GraphDatabase, Record
from neo4j.exceptions import (
    AuthError,
    ConstraintError,
    CypherSyntaxError,
    Neo4jError,
    ServiceUnavailable,
    SessionExpired,
    TransientError,
)

from . import exceptions as exc

logger = logging.getLogger(__name__)


class Neo4jClient:
    """Thin, production-oriented wrapper around the official Neo4j Python driver."""

    def __init__(
        self,
        uri: str,
        user: str,
        password: str,
        database: str = "neo4j",
        max_pool_size: int = 50,
        connection_timeout: float = 30.0,
    ) -> None:
        self._database = database
        self._closed = False
        try:
            # Pool + timeout set on the driver; fetch_size applied per session
            # so large result sets stream in batches of 1000 records.
            self._driver = GraphDatabase.driver(
                uri,
                auth=(user, password),
                max_connection_pool_size=max_pool_size,
                connection_timeout=connection_timeout,
            )
            self._fetch_size = 1000
            self._driver.verify_connectivity()
        except AuthError as err:
            raise exc.ConnectionError(
                "Neo4j authentication failed",
                details={"uri": uri, "cause": str(err)},
            ) from err
        except (ServiceUnavailable, SessionExpired, OSError) as err:
            raise exc.ConnectionError(
                "Neo4j cluster/instance unreachable",
                details={"uri": uri, "cause": str(err)},
            ) from err
        except Neo4jError as err:
            raise exc.ConnectionError(
                "Neo4j connectivity verification failed",
                details={"uri": uri, "cause": str(err)},
            ) from err

        atexit.register(self.close)
        logger.info(
            "Neo4jClient connected uri=%s database=%s pool=%s timeout=%ss",
            uri,
            database,
            max_pool_size,
            connection_timeout,
        )

    def verify_connectivity(self) -> None:
        """Re-check Bolt connectivity; raises ConnectionError on failure."""
        try:
            self._driver.verify_connectivity()
        except AuthError as err:
            raise exc.ConnectionError(
                "Neo4j authentication failed",
                details={"cause": str(err)},
            ) from err
        except (ServiceUnavailable, SessionExpired, OSError) as err:
            raise exc.ConnectionError(
                "Neo4j cluster/instance unreachable",
                details={"cause": str(err)},
            ) from err
        except Neo4jError as err:
            raise exc.ConnectionError(
                "Neo4j connectivity verification failed",
                details={"cause": str(err)},
            ) from err

    def close(self) -> None:
        """Close the underlying driver. Safe to call multiple times."""
        if self._closed:
            return
        self._closed = True
        try:
            self._driver.close()
            logger.info("Neo4jClient driver closed")
        except Exception as err:  # noqa: BLE001 — close must not raise during shutdown
            logger.warning("Error while closing Neo4j driver: %s", err)

    def __enter__(self) -> "Neo4jClient":
        return self

    def __exit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc_val: Optional[BaseException],
        exc_tb: Optional[TracebackType],
    ) -> None:
        self.close()

    def execute_read(
        self, query: str, parameters: Optional[dict[str, Any]] = None
    ) -> list[Record]:
        """Public read API — delegates to ``_execute_read`` (managed transaction)."""
        return self._execute_read(query, parameters or {})

    def execute_write(
        self, query: str, parameters: Optional[dict[str, Any]] = None
    ) -> list[Record]:
        """Public write API — delegates to ``_execute_write`` (managed transaction)."""
        return self._execute_write(query, parameters or {})

    def _execute_read(self, query: str, parameters: dict[str, Any]) -> list[Record]:
        """
        Run a read query inside ``session.execute_read``.

        Managed transactions provide automatic retry on transient cluster errors;
        do not call ``session.run`` directly from public methods.
        """
        return self._run_managed(query, parameters, write=False)

    def _execute_write(self, query: str, parameters: dict[str, Any]) -> list[Record]:
        """
        Run a write query inside ``session.execute_write``.

        Same retry/logging semantics as :meth:`_execute_read`.
        """
        return self._run_managed(query, parameters, write=True)

    def _run_managed(
        self, query: str, parameters: dict[str, Any], *, write: bool
    ) -> list[Record]:
        started = time.perf_counter()
        param_count = len(parameters)
        mode = "WRITE" if write else "READ"
        logger.info(
            "Neo4j %s start param_count=%s query_preview=%r",
            mode,
            param_count,
            query[:120].replace("\n", " "),
        )

        def work(tx: Any) -> list[Record]:
            result = tx.run(query, parameters)
            return list(result)

        try:
            with self._driver.session(
                database=self._database, fetch_size=self._fetch_size
            ) as session:
                if write:
                    records = session.execute_write(work)
                else:
                    records = session.execute_read(work)
        except (exc.ConnectionError, exc.QueryError, exc.TimeoutError, exc.DataError):
            raise
        except AuthError as err:
            raise exc.ConnectionError(
                "Authentication failed during query",
                details={"cause": str(err)},
            ) from err
        except (ServiceUnavailable, SessionExpired) as err:
            raise exc.ConnectionError(
                "Service unavailable during query",
                details={"cause": str(err)},
            ) from err
        except (CypherSyntaxError, ConstraintError) as err:
            raise exc.QueryError(
                "Cypher syntax or constraint violation",
                details={"cause": str(err)},
            ) from err
        except TransientError as err:
            # Exhausted retries or timeout-class transient failures
            message = str(err).lower()
            if "timeout" in message or "timed out" in message:
                raise exc.TimeoutError(
                    "Neo4j transaction or connection timed out",
                    details={"cause": str(err)},
                ) from err
            raise exc.QueryError(
                "Transient Neo4j error after retries",
                details={"cause": str(err)},
            ) from err
        except Neo4jError as err:
            message = str(err).lower()
            if "timeout" in message or "timed out" in message:
                raise exc.TimeoutError(
                    "Neo4j operation timed out",
                    details={"cause": str(err)},
                ) from err
            raise exc.QueryError(
                "Neo4j query failed",
                details={"cause": str(err), "code": getattr(err, "code", None)},
            ) from err
        except Exception as err:  # noqa: BLE001
            raise exc.QueryError(
                "Unexpected error executing Neo4j query",
                details={"cause": str(err)},
            ) from err

        duration_ms = (time.perf_counter() - started) * 1000
        logger.info(
            "Neo4j %s done result_count=%s duration_ms=%.2f param_count=%s",
            mode,
            len(records),
            duration_ms,
            param_count,
        )
        return records
