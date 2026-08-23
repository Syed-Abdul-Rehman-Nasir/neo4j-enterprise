"""Prometheus metrics proxy and threshold evaluation."""

from __future__ import annotations

import time
from typing import Any, Optional

import httpx

from python.api.schemas.common import HealthStatus
from python.api.schemas.operations import MetricPoint, MetricSeriesResponse

# Canonical thresholds from the assessment monitoring catalog
THRESHOLDS: dict[str, dict[str, float]] = {
    "heap_utilization": {"warning": 80.0, "critical": 90.0},
    "query_latency_p95": {"warning": 2000.0, "critical": 5000.0},
    "page_cache_hit_ratio": {"warning": 97.0, "critical": 95.0},  # below
    "replication_lag": {"warning": 5000.0, "critical": 30000.0},
    "disk_usage": {"warning": 70.0, "critical": 80.0},
    "active_transactions": {"warning": 100.0, "critical": 200.0},
}

PROM_QUERIES: dict[str, tuple[str, str]] = {
    # metric_key -> (promql, unit)
    "heap_utilization": (
        '(neo4j_vm_heap_used{*} / neo4j_vm_heap_max{*}) * 100',
        "%",
    ),
    "query_latency_p95": (
        "histogram_quantile(0.95, sum(rate(neo4j_db_query_execution_latency_ms_bucket[5m])) by (le))",
        "ms",
    ),
    "page_cache_hit_ratio": (
        "(sum(rate(neo4j_page_cache_hits_total[5m])) / "
        "(sum(rate(neo4j_page_cache_hits_total[5m])) + sum(rate(neo4j_page_cache_faults_total[5m])))) * 100",
        "%",
    ),
    "replication_lag": ("neo4j_cluster_raft_replication_lag", "ms"),
    "active_transactions": ("neo4j_transaction_active", "count"),
    "committed_transactions": ("rate(neo4j_transaction_committed_total[1m])", "tx/s"),
    "gc_pause": ("rate(neo4j_vm_gc_time[1m])", "ms/s"),
}


def _status_for(metric: str, value: Optional[float]) -> HealthStatus:
    if value is None:
        return "unknown"
    th = THRESHOLDS.get(metric)
    if not th:
        return "healthy"
    if metric == "page_cache_hit_ratio":
        if value < th["critical"]:
            return "critical"
        if value < th["warning"]:
            return "warning"
        return "healthy"
    if value >= th.get("critical", float("inf")):
        return "critical"
    if value >= th.get("warning", float("inf")):
        return "warning"
    return "healthy"


class MetricsService:
    def __init__(self, prometheus_url: str) -> None:
        self._base = prometheus_url.rstrip("/")

    def fetch_metrics(
        self, metrics: list[str], window: str = "15m", step: str = "15s"
    ) -> list[MetricSeriesResponse]:
        end = time.time()
        # parse simple windows like 15m, 1h
        seconds = 900
        if window.endswith("m"):
            seconds = int(window[:-1]) * 60
        elif window.endswith("h"):
            seconds = int(window[:-1]) * 3600
        start = end - seconds

        out: list[MetricSeriesResponse] = []
        keys = metrics or list(PROM_QUERIES.keys())
        for key in keys:
            if key not in PROM_QUERIES:
                out.append(
                    MetricSeriesResponse(
                        metric=key,
                        unit="",
                        status="unknown",
                        thresholds={},
                        points=[],
                        source="prometheus",
                        detail="Unknown metric key",
                    )
                )
                continue
            promql, unit = PROM_QUERIES[key]
            series = self._query_range(promql, start, end, step)
            latest = series[-1].value if series else None
            out.append(
                MetricSeriesResponse(
                    metric=key,
                    unit=unit,
                    status=_status_for(key, latest),
                    thresholds=THRESHOLDS.get(key, {}),
                    points=series,
                    source=f"{self._base}/api/v1/query_range",
                    detail=None if series else "Prometheus series unavailable",
                )
            )
        return out

    def _query_range(
        self, query: str, start: float, end: float, step: str
    ) -> list[MetricPoint]:
        try:
            with httpx.Client(timeout=5.0) as client:
                resp = client.get(
                    f"{self._base}/api/v1/query_range",
                    params={"query": query, "start": start, "end": end, "step": step},
                )
                if resp.status_code != 200:
                    return []
                payload = resp.json()
                result = payload.get("data", {}).get("result", [])
                if not result:
                    return []
                values = result[0].get("values", [])
                points: list[MetricPoint] = []
                for ts, val in values:
                    try:
                        points.append(MetricPoint(timestamp=float(ts), value=float(val)))
                    except (TypeError, ValueError):
                        points.append(MetricPoint(timestamp=float(ts), value=None))
                return points
        except Exception:
            return []

    def prometheus_reachable(self) -> bool:
        try:
            with httpx.Client(timeout=2.0) as client:
                resp = client.get(f"{self._base}/-/ready")
                return resp.status_code == 200
        except Exception:
            return False
