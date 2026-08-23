"""Serialize Neo4j values to JSON-safe Python types."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from neo4j.graph import Node, Path, Relationship
from neo4j.time import Date, DateTime, Time


def serialize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, bool, float)):
        return value
    if isinstance(value, int):
        return int(value)
    if hasattr(value, "to_native"):
        try:
            return serialize_value(value.to_native())
        except Exception:
            pass
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, (DateTime, Date, Time)):
        try:
            return value.iso_format()
        except Exception:
            return str(value)
    if isinstance(value, Node):
        return {
            "elementId": value.element_id,
            "labels": list(value.labels),
            "properties": {k: serialize_value(v) for k, v in dict(value).items()},
        }
    if isinstance(value, Relationship):
        return {
            "elementId": value.element_id,
            "type": value.type,
            "properties": {k: serialize_value(v) for k, v in dict(value).items()},
        }
    if isinstance(value, Path):
        return {
            "nodes": [serialize_value(n) for n in value.nodes],
            "relationships": [serialize_value(r) for r in value.relationships],
        }
    if isinstance(value, (list, tuple)):
        return [serialize_value(v) for v in value]
    if isinstance(value, dict):
        return {k: serialize_value(v) for k, v in value.items()}
    # neo4j.Integer
    if type(value).__name__ == "Integer":
        return int(value)
    return str(value)


def record_to_dict(record: Any) -> dict[str, Any]:
    return {key: serialize_value(record[key]) for key in record.keys()}


LABEL_ID_KEYS = {
    "Employee": "employeeId",
    "Department": "deptId",
    "Application": "applicationId",
    "Service": "serviceId",
    "Database": "databaseId",
    "Server": "serverId",
    "Incident": "incidentId",
}


def node_business_id(labels: list[str], props: dict[str, Any], element_id: str) -> str:
    for label in labels:
        key = LABEL_ID_KEYS.get(label)
        if key and props.get(key) is not None:
            return str(props[key])
    return element_id


def node_display_name(labels: list[str], props: dict[str, Any], fallback: str) -> str:
    if props.get("name"):
        return str(props["name"])
    if props.get("title"):
        return str(props["title"])
    return fallback
