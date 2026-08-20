"""Immutable result models for Neo4j query shapes.

Each dataclass is frozen and provides ``from_record`` / ``to_dict`` for safe
extraction from ``neo4j.Record`` and JSON serialization.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Mapping, Optional

from .exceptions import DataError


def _get(record: Mapping[str, Any], *keys: str, default: Any = None) -> Any:
    """Return the first present key from a record-like mapping."""
    for key in keys:
        try:
            if hasattr(record, "get"):
                value = record.get(key)  # type: ignore[attr-defined]
            else:
                value = record[key] if key in record else None
        except Exception:
            value = None
        if value is not None:
            return value
    return default


def _require(record: Mapping[str, Any], *keys: str, field: str) -> Any:
    value = _get(record, *keys)
    if value is None:
        raise DataError(
            f"Unexpected null/missing field '{field}' in Neo4j record",
            details={"field": field, "tried_keys": list(keys)},
        )
    return value


@dataclass(frozen=True)
class DependencyChain:
    employee: str
    application: str
    applicationId: str
    service: str
    serviceType: str
    database: str
    dbEngine: str
    criticality: float

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "DependencyChain":
        try:
            return cls(
                employee=str(_require(record, "employee", "employee_name", field="employee")),
                application=str(
                    _require(record, "application", "application_name", field="application")
                ),
                applicationId=str(
                    _require(record, "applicationId", "application_id", field="applicationId")
                ),
                service=str(_require(record, "service", "service_name", field="service")),
                serviceType=str(
                    _require(record, "serviceType", "service_type", field="serviceType")
                ),
                database=str(_require(record, "database", "database_name", field="database")),
                dbEngine=str(_require(record, "dbEngine", "database_engine", field="dbEngine")),
                criticality=float(
                    _get(record, "criticality", "dependency_weight", "dependency_criticality", default=0.0)
                ),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError("Failed to parse DependencyChain from record", details={"cause": str(exc)}) from exc

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class IncidentSummary:
    incidentId: str
    title: str
    severity: str
    status: str
    applicationName: str
    mttr_minutes: Optional[int]

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "IncidentSummary":
        try:
            mttr = _get(record, "mttr_minutes", "mttrMinutes")
            return cls(
                incidentId=str(_require(record, "incidentId", "incident_id", field="incidentId")),
                title=str(_require(record, "title", field="title")),
                severity=str(_require(record, "severity", field="severity")),
                status=str(_require(record, "status", field="status")),
                applicationName=str(
                    _require(record, "applicationName", "application_name", field="applicationName")
                ),
                mttr_minutes=int(mttr) if mttr is not None else None,
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError("Failed to parse IncidentSummary from record", details={"cause": str(exc)}) from exc

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class ImpactedEmployee:
    name: str
    email: str
    role: str
    department: str
    viaApplication: str
    viaService: str

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "ImpactedEmployee":
        try:
            return cls(
                name=str(_require(record, "name", "impacted_employee", field="name")),
                email=str(_require(record, "email", field="email")),
                role=str(_get(record, "role", default="")),
                department=str(_require(record, "department", field="department")),
                viaApplication=str(
                    _require(record, "viaApplication", "via_application", field="viaApplication")
                ),
                viaService=str(_require(record, "viaService", "via_service", field="viaService")),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError("Failed to parse ImpactedEmployee from record", details={"cause": str(exc)}) from exc

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class ApplicationStats:
    name: str
    applicationId: str
    tier: int
    uniqueUsers: int
    incidentCount: int

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "ApplicationStats":
        try:
            return cls(
                name=str(_require(record, "name", "application_name", field="name")),
                applicationId=str(
                    _require(record, "applicationId", "application_id", field="applicationId")
                ),
                tier=int(_require(record, "tier", field="tier")),
                uniqueUsers=int(_get(record, "uniqueUsers", "unique_users", "user_count", default=0)),
                incidentCount=int(
                    _get(record, "incidentCount", "incident_count", default=0)
                ),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError("Failed to parse ApplicationStats from record", details={"cause": str(exc)}) from exc

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class FullDownstreamChain:
    application: str
    appVersion: str
    service: str
    svcType: str
    svcSlaMs: int
    database: str
    dbEngine: str
    dbSizeGb: float
    server: str
    serverRegion: str
    serverOs: str
    criticality: float

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "FullDownstreamChain":
        try:
            return cls(
                application=str(_require(record, "application", field="application")),
                appVersion=str(_require(record, "appVersion", "app_version", field="appVersion")),
                service=str(_require(record, "service", field="service")),
                svcType=str(_require(record, "svcType", "svc_type", field="svcType")),
                svcSlaMs=int(_require(record, "svcSlaMs", "svc_sla_ms", "svcSlaMss", field="svcSlaMs")),
                database=str(_require(record, "database", field="database")),
                dbEngine=str(_require(record, "dbEngine", "db_engine", field="dbEngine")),
                dbSizeGb=float(_require(record, "dbSizeGb", "db_size_gb", field="dbSizeGb")),
                server=str(_require(record, "server", field="server")),
                serverRegion=str(
                    _require(record, "serverRegion", "server_region", field="serverRegion")
                ),
                serverOs=str(_require(record, "serverOs", "server_os", field="serverOs")),
                criticality=float(
                    _get(record, "criticality", "dependency_criticality", default=0.0)
                ),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError(
                "Failed to parse FullDownstreamChain from record", details={"cause": str(exc)}
            ) from exc

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class DependencyPath:
    path_nodes: list[str]
    hops: int

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "DependencyPath":
        try:
            nodes = _require(record, "path_nodes", "node_names", field="path_nodes")
            return cls(
                path_nodes=[str(n) for n in list(nodes)],
                hops=int(_require(record, "hops", "hop_count", field="hops")),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError(
                "Failed to parse DependencyPath from record", details={"cause": str(exc)}
            ) from exc

    def to_dict(self) -> dict[str, Any]:
        return {"path_nodes": self.path_nodes, "hops": self.hops}


@dataclass(frozen=True)
class SharedDatabaseEmployee:
    employee: str
    shared_database: str
    applications: list[str]
    app_count: int

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "SharedDatabaseEmployee":
        try:
            apps = _require(record, "applications", field="applications")
            return cls(
                employee=str(
                    _require(record, "employee", "employee_name", field="employee")
                ),
                shared_database=str(
                    _require(record, "shared_database", field="shared_database")
                ),
                applications=[str(a) for a in list(apps)],
                app_count=int(_require(record, "app_count", field="app_count")),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError(
                "Failed to parse SharedDatabaseEmployee from record",
                details={"cause": str(exc)},
            ) from exc

    def to_dict(self) -> dict[str, Any]:
        return {
            "employee": self.employee,
            "shared_database": self.shared_database,
            "applications": self.applications,
            "app_count": self.app_count,
        }


@dataclass(frozen=True)
class ApplicationSummary:
    application: str
    id: str
    owner: str
    tier: int

    @classmethod
    def from_record(cls, record: Mapping[str, Any]) -> "ApplicationSummary":
        try:
            return cls(
                application=str(_require(record, "application", field="application")),
                id=str(_require(record, "id", "applicationId", field="id")),
                owner=str(_require(record, "owner", field="owner")),
                tier=int(_require(record, "tier", field="tier")),
            )
        except DataError:
            raise
        except Exception as exc:
            raise DataError(
                "Failed to parse ApplicationSummary from record",
                details={"cause": str(exc)},
            ) from exc

    def to_dict(self) -> dict[str, Any]:
        return {
            "application": self.application,
            "id": self.id,
            "owner": self.owner,
            "tier": self.tier,
        }
