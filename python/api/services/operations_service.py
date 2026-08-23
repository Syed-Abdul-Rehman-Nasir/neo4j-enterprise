"""Operations summary, alerts, and runbook metadata."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from python.api.schemas.common import HealthStatus
from python.api.schemas.operations import (
    AlertDefinition,
    ClusterMember,
    OperationsSummary,
    RunbookStep,
)
from python.neo4j_client import Neo4jClient

REPO_ROOT = Path(__file__).resolve().parents[3]
ALERTS_PATH = REPO_ROOT / "monitoring" / "datadog_alerts.json"


class OperationsService:
    def __init__(self, client: Neo4jClient) -> None:
        self._client = client

    def summary(self) -> OperationsSummary:
        constraint_count = 0
        index_count = 0
        db_status = "unknown"
        try:
            crows = self._client.execute_read(
                "SHOW CONSTRAINTS YIELD name RETURN count(name) AS c", {}
            )
            if crows:
                constraint_count = int(crows[0]["c"])
            irows = self._client.execute_read(
                "SHOW INDEXES YIELD name, state WHERE state = 'ONLINE' RETURN count(name) AS c",
                {},
            )
            if irows:
                index_count = int(irows[0]["c"])
            drows = self._client.execute_read(
                "SHOW DATABASES YIELD name, currentStatus "
                "WHERE name = 'neo4j' RETURN currentStatus AS status",
                {},
            )
            if drows:
                db_status = str(drows[0]["status"])
        except Exception:
            pass

        members: list[ClusterMember] = []
        mode = "standalone"
        try:
            mrows = self._client.execute_read(
                "CALL dbms.cluster.overview() YIELD id, addresses, role "
                "RETURN id, addresses, role",
                {},
            )
            if mrows:
                mode = "cluster"
                for r in mrows:
                    addr = ""
                    addresses = r.get("addresses") or []
                    if addresses:
                        addr = str(addresses[0])
                    members.append(
                        ClusterMember(role=str(r.get("role") or "UNKNOWN"), address=addr, status="online")
                    )
        except Exception:
            members = [
                ClusterMember(role="STANDALONE", address="local", status=db_status or "online")
            ]

        health: HealthStatus = "healthy" if db_status in {"online", "unknown"} and constraint_count >= 12 else "warning"
        if constraint_count == 0:
            health = "unknown"

        return OperationsSummary(
            mode=mode if mode == "cluster" else "standalone",
            label="Standalone lab" if mode != "cluster" else "Live cluster",
            productionTargetLabel="Production target: 3 Raft cores + 2 analytics replicas + 1 backup replica",
            members=members,
            databaseStatus=db_status,
            constraintCount=constraint_count,
            indexOnlineCount=index_count,
            replicationLagMs=None,
            health=health,
        )

    def alerts(self) -> list[AlertDefinition]:
        if not ALERTS_PATH.exists():
            return []
        raw = json.loads(ALERTS_PATH.read_text(encoding="utf-8"))
        out: list[AlertDefinition] = []
        for item in raw[:6]:
            opts = item.get("options") or {}
            thresholds = opts.get("thresholds") or {}
            tags = item.get("tags") or []
            severity = "p2"
            for t in tags:
                if isinstance(t, str) and t.startswith("severity:"):
                    severity = t.split(":", 1)[1]
            out.append(
                AlertDefinition(
                    name=str(item.get("name") or "Alert"),
                    severity=severity,
                    query=str(item.get("query") or ""),
                    message=str(item.get("message") or ""),
                    thresholds={k: float(v) for k, v in thresholds.items()},
                    evaluatedStatus="unknown",
                    tags=[str(t) for t in tags],
                )
            )
        return out

    def runbook(self) -> list[RunbookStep]:
        return [
            RunbookStep(
                id="step-1",
                title="Identify runaway queries",
                summary="List active queries and kill only after confirming impact.",
                commands=[
                    "CALL dbms.listQueries() YIELD queryId, username, elapsedTimeMillis, query RETURN * ORDER BY elapsedTimeMillis DESC",
                    "CALL dbms.killQuery('<queryId>')",
                ],
                thresholds=["p95 latency > 2000ms warning", "p95 latency > 5000ms critical"],
            ),
            RunbookStep(
                id="step-2",
                title="Inspect transactions and locks",
                summary="Find long-running or blocked transactions before restarting.",
                commands=[
                    "CALL dbms.listTransactions() YIELD transactionId, elapsedTime, currentQuery RETURN *",
                ],
                thresholds=["active transactions > 100 warning", "> 200 critical"],
            ),
            RunbookStep(
                id="step-3",
                title="Validate page cache and heap",
                summary="Confirm hit ratio and heap headroom before resizing memory.",
                commands=[
                    "CALL dbms.queryJmx('org.neo4j:instance=kernel#0,name=Page cache')",
                ],
                thresholds=["page cache hit ratio < 97% warning", "< 95% critical", "heap > 80%/90%"],
            ),
            RunbookStep(
                id="step-4",
                title="Check cluster membership and lag",
                summary="In production, verify Raft quorum and replication lag.",
                commands=[
                    "CALL dbms.cluster.overview()",
                    "CALL dbms.cluster.role()",
                ],
                thresholds=["replication lag > 5s warning", "> 30s critical"],
            ),
            RunbookStep(
                id="step-5",
                title="Disk, store size, and checkpoints",
                summary="Confirm free disk and checkpoint health; prune only after successful backup.",
                commands=[
                    "SHOW DATABASES YIELD name, currentStatus, storeSize",
                ],
                thresholds=["disk > 70% warning", "> 80% critical"],
            ),
            RunbookStep(
                id="step-6",
                title="Backup verification and restore readiness",
                summary="Backups are operator-controlled; UI never triggers restore.",
                commands=[
                    "neo4j-admin database backup neo4j --to-path=/backups",
                    "./admin/cluster_health_check.sh",
                ],
                thresholds=["RPO/RTO per admin/backup.sh documentation"],
            ),
        ]
