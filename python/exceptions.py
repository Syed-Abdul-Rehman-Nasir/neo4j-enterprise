"""Custom exception hierarchy for the Neo4j client.

Exceptions expose ``to_dict()`` so API layers can serialize errors to JSON
without leaking driver internals.
"""

from __future__ import annotations

from typing import Any, Optional


class Neo4jClientError(Exception):
    """Base error for all Neo4j client failures."""

    def __init__(self, message: str, details: Optional[dict[str, Any]] = None) -> None:
        super().__init__(message)
        self.message = message
        self.details: dict[str, Any] = details or {}

    def to_dict(self) -> dict[str, Any]:
        return {
            "error": self.__class__.__name__,
            "message": self.message,
            "details": self.details,
        }


class ConnectionError(Neo4jClientError):
    """Cluster unreachable, authentication failure, or connectivity verification failed."""

    def to_dict(self) -> dict[str, Any]:
        payload = super().to_dict()
        payload["category"] = "connection"
        return payload


class QueryError(Neo4jClientError):
    """Cypher syntax error, constraint violation, or other query execution failure."""

    def to_dict(self) -> dict[str, Any]:
        payload = super().to_dict()
        payload["category"] = "query"
        return payload


class TimeoutError(Neo4jClientError):
    """Transaction or connection timeout exceeded."""

    def to_dict(self) -> dict[str, Any]:
        payload = super().to_dict()
        payload["category"] = "timeout"
        return payload


class DataError(Neo4jClientError):
    """Result parsing failure or unexpected null / missing field."""

    def to_dict(self) -> dict[str, Any]:
        payload = super().to_dict()
        payload["category"] = "data"
        return payload
