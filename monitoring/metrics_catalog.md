# Neo4j Prometheus Metrics Catalog

Operator reference for metrics scraped from the Neo4j Enterprise Prometheus endpoint (`:2004/metrics`). Aligns with [`prometheus.yml`](prometheus.yml), [`admin/troubleshooting_runbook.md`](../admin/troubleshooting_runbook.md), and [`cypher/performance/query_tuning_notes.md`](../cypher/performance/query_tuning_notes.md).

Exact metric names can vary slightly by Neo4j 5.x patch and database label; treat names below as the canonical Neo4j Prometheus family names used in this assessment stack.

---

## 1. Page cache hits / misses → hit ratio

| | |
|---|---|
| **Metric names** | `neo4j_db_page_cache_hits_total`, `neo4j_db_page_cache_misses_total` |
| **Measures** | Cumulative page-cache hits vs misses. Derived **hit_ratio** = `hits / (hits + misses)`. |
| **Normal range** | Hit ratio **> 99%** (OLTP); **≥ 97%** operational floor. |
| **Warning** | Hit ratio **< 97%** sustained > 5–10 minutes. |
| **Critical** | Hit ratio **< 95%**; rising miss rate with latency spikes. |
| **Actions** | **Warn:** correlate with cold start / import / index population; warm caches; review heavy scans. **Critical:** increase `server.memory.pagecache.size`, offload analytics to a replica, kill disk-bound runaway queries (see runbook Steps 1 & 5). |

---

## 2. JVM heap used vs max

| | |
|---|---|
| **Metric names** | `neo4j_jvm_memory_heap_used_bytes`, `neo4j_jvm_memory_heap_max_bytes` |
| **Measures** | Live heap occupancy vs configured maximum heap. |
| **Normal range** | Utilization typically **40–75%** under steady OLTP; headroom for spikes. |
| **Warning** | Utilization **> 80%** sustained (`used / max × 100`). |
| **Critical** | Utilization **> 90%**, frequent full GC, or OOM risk. |
| **Actions** | **Warn:** inspect large transactions / `COLLECT`; set `dbms.memory.transaction.total.max`. **Critical:** kill bloated txs (runbook Step 2); plan heap resize (initial == max, usually ≤ 16g) with restart; prefer pagecache over oversized heap. |

---

## 3. JVM GC pause time

| | |
|---|---|
| **Metric name** | `neo4j_jvm_gc_pause_time_seconds_total` |
| **Measures** | Cumulative time spent in GC pauses (rate over time = pause intensity). |
| **Normal range** | Low, flat rate; p99 application latency not dominated by GC. |
| **Warning** | GC pause rate rising; young/old GC frequency up with heap > 80%. |
| **Critical** | Multi-second pauses, allocation failures in `debug.log`, or latency cliffs aligned with GC. |
| **Actions** | **Warn:** reduce heap churn (query memory, transaction size). **Critical:** tune/restart with equal heap sizes; lower concurrent tx memory; escalate GC log review (`grep GC debug.log`). |

---

## 4. Query execution latency (histogram)

| | |
|---|---|
| **Metric name** | `neo4j_db_query_execution_latency_milliseconds` (histogram buckets / `_bucket`, `_sum`, `_count`) |
| **Measures** | Distribution of Cypher execution latency in milliseconds. |
| **Normal range** | p50 / p95 within SLO (e.g. p95 **< 200–500 ms** for interactive OLTP; adjust to your SLA). |
| **Warning** | p95 **> 2000 ms** while traffic is steady. |
| **Critical** | p95 **> 5000 ms**, widespread timeouts, or latency matching incident symptoms. |
| **Actions** | **Warn:** enable/inspect query log (`db.logs.query.threshold`); `EXPLAIN`/`PROFILE` top offenders. **Critical:** runbook Step 1 (`listQueries` / `killQuery`); fix missing indexes; not “add CPU” until Cypher vs infra is distinguished. |

---

## 5. Active transactions

| | |
|---|---|
| **Metric name** | `neo4j_db_transaction_active` |
| **Measures** | Number of currently open transactions. |
| **Normal range** | Small relative to pool/concurrency limits; no long-lived growth. |
| **Warning** | Active transactions **> 100**. |
| **Critical** | Active transactions **> 200**, or spike with BLOCKED txs / lock waits. |
| **Actions** | **Warn:** identify long runners via `listTransactions`. **Critical:** `killTransaction` for stale/blocked txs; check for missing commits in clients. |

---

## 6. Committed transactions

| | |
|---|---|
| **Metric name** | `neo4j_db_transaction_committed_total` |
| **Measures** | Cumulative successfully committed transactions (throughput signal via rate). |
| **Normal range** | Stable commit rate matching application load. |
| **Warning** | Unexpected drop in commit rate with rising client errors. |
| **Critical** | Near-zero commits while traffic continues (DB stuck / unavailable). |
| **Actions** | **Warn:** check Bolt errors, leader health, disk. **Critical:** cluster/database status (`SHOW DATABASES`), failover / restore procedures if store unhealthy. |

---

## 7. Transaction rollbacks

| | |
|---|---|
| **Metric name** | `neo4j_db_transaction_rollbacks_total` |
| **Measures** | Cumulative rolled-back transactions (failures, conflicts, explicit rollback). |
| **Normal range** | Low absolute rate; rollback rate ≪ commit rate. |
| **Warning** | Derived rollback rate **> 1–2%** of commits sustained. |
| **Critical** | Rollback rate **> 5–10%** or sharp spike with constraint/deadlock errors. |
| **Actions** | **Warn:** review app retry logic and constraint violations. **Critical:** inspect query log / client errors; fix conflicting writers; check disk/full tx log issues. |

---

## 8. Cluster unreachable discovery members

| | |
|---|---|
| **Metric name** | `neo4j_cluster_discovery_unreachable_members` |
| **Measures** | Count of cluster members currently unreachable via discovery. |
| **Normal range** | **0** in a healthy cluster. |
| **Warning** | **1** member unreachable briefly (network blip / rolling restart). |
| **Critical** | **≥ 1** sustained, or count that threatens quorum (e.g. majority loss). |
| **Actions** | **Warn:** verify host/network; watch during planned maintenance. **Critical:** restore connectivity; confirm leadership (`cluster_health_check.sh`); do not run schema-heavy ops until quorum stable. |

---

## 9. Raft replication lag

| | |
|---|---|
| **Metric name** | `neo4j_cluster_raft_replication_lag` |
| **Measures** | Replication / raft lag (ms or entries depending on export — treat as lag magnitude). |
| **Normal range** | Near **0–hundreds of ms** under healthy links. |
| **Warning** | Lag **> 5000 ms** (aligns with `cluster_health_check.sh`). |
| **Critical** | Lag **> 30000 ms** or growing without bound. |
| **Actions** | **Warn:** check network I/O, disk on followers, catch-up state. **Critical:** pause heavy writers if needed; investigate slow secondaries; validate store/disk health. |

---

## 10. Store size

| | |
|---|---|
| **Metric name** | `neo4j_db_store_size_total_bytes` |
| **Measures** | On-disk size of the database store files. |
| **Normal range** | Matches expected data growth; smooth trend. |
| **Warning** | Sudden step-up unexplained by imports; approaching volume capacity (**> 70%** disk). |
| **Critical** | Disk near full (**> 80%**) or unbounded growth without data ingest. |
| **Actions** | **Warn:** confirm ETL volume; plan capacity. **Critical:** free disk; check tx logs vs store (runbook Step 6); ensure backups/checkpoints prune logs. |

---

## 11. Checkpoint duration

| | |
|---|---|
| **Metric name** | `neo4j_db_checkpoint_duration_milliseconds` |
| **Measures** | Time taken by store checkpoints. |
| **Normal range** | Short relative to checkpoint interval; no multi-minute stalls. |
| **Warning** | Durations trending up; checkpoints overlapping heavy query load. |
| **Critical** | Very long checkpoints causing I/O saturation and latency spikes. |
| **Actions** | **Warn:** review I/O and page cache. **Critical:** reduce concurrent heavy scans during checkpoint; check disk throughput; manually `CALL db.checkpoint()` only with care during incidents. |

---

## 12. Bolt connections opened

| | |
|---|---|
| **Metric name** | `neo4j_bolt_connections_opened_total` |
| **Measures** | Cumulative Bolt connections opened (rate = connection open rate). |
| **Normal range** | Matches pool sizing / client pool behavior; stable open rate. |
| **Warning** | Open rate rising without traffic growth (possible pool misconfig / reconnect storm). |
| **Critical** | Exhaustion of connection limits; clients failing to connect. |
| **Actions** | **Warn:** review driver `max_connection_pool_size` and idle lifetime. **Critical:** check auth storms, LB health checks, and Neo4j `server.bolt` limits. |

---

## 13. Bolt connections closed

| | |
|---|---|
| **Metric name** | `neo4j_bolt_connections_closed_total` |
| **Measures** | Cumulative Bolt connections closed (pair with opened for churn). |
| **Normal range** | Close rate ≈ open rate at steady state. |
| **Warning** | Elevated churn (opens and closes) vs baseline. |
| **Critical** | Mass disconnects aligned with timeouts, OOMs, or network partitions. |
| **Actions** | **Warn:** investigate idle timeouts and client errors. **Critical:** correlate with GC/heap and network; stabilize instance before scaling clients. |

---

## 14. Node IDs in use

| | |
|---|---|
| **Metric name** | `neo4j_ids_in_use_node_ids` |
| **Measures** | Approximate count of node IDs currently in use (graph size proxy). |
| **Normal range** | Tracks known data volume; matches import expectations. |
| **Warning** | Unexpected rapid growth or sudden drop (mass delete / wrong DB). |
| **Critical** | Growth threatening capacity plans or collapse indicating data loss. |
| **Actions** | **Warn:** validate ETL jobs and counts vs source systems. **Critical:** stop bad deletes; restore from backup if corruption/loss suspected. |

---

## 15. Relationship IDs in use

| | |
|---|---|
| **Metric name** | `neo4j_ids_in_use_relationship_ids` |
| **Measures** | Approximate count of relationship IDs in use (edge cardinality proxy). |
| **Normal range** | Proportional to node growth and known model density. |
| **Warning** | Relationship growth far outpacing nodes (runaway edge creation / Cartesian writes). |
| **Critical** | Explosive growth causing store/disk pressure. |
| **Actions** | **Warn:** audit write pipelines and MERGE patterns. **Critical:** halt offending writers; investigate with query log; capacity + restore if needed. |

---

## Derived Metrics to Calculate in Datadog

Define these as Datadog calculated metrics / monitors (PromQL or Datadog query formulas):

| Derived metric | Formula |
|---|---|
| **Page cache hit ratio** | `hits / (hits + misses)` using `neo4j_db_page_cache_hits_total` and `neo4j_db_page_cache_misses_total` (prefer `rate()` then ratio, or `increase()` over the same window). |
| **Transaction rollback rate** | `rollbacks / committed` → `neo4j_db_transaction_rollbacks_total / neo4j_db_transaction_committed_total` (use rates over a shared time window). |
| **Heap utilization %** | `heap_used / heap_max × 100` → `neo4j_jvm_memory_heap_used_bytes / neo4j_jvm_memory_heap_max_bytes * 100`. |
| **Query error rate** | `failed_queries / total_queries × 100` (from query failure counters / latency count vs error metrics available in your Neo4j export — wire the matching `neo4j_db_query_*` failure series). |
| **Connection churn rate** | `connections_closed / time_interval` → `rate(neo4j_bolt_connections_closed_total)` (or `increase` over the monitor window). |

**Suggested Datadog alert hooks**

- Hit ratio < 97% (warn) / < 95% (critical)
- Heap utilization > 80% (warn) / > 90% (critical)
- Query latency p95 > 2000 ms (warn) / > 5000 ms (critical)
- Replication lag > 5s (warn) / > 30s (critical)
- Disk usage > 70% (warn) / > 80% (critical)
- Active transactions > 100 (warn) / > 200 (critical)
- Rollback rate > 2% (warn) / > 5% (critical)

---

*Catalog version aligned with Neo4j 5.23 Enterprise assessment stack. Re-verify metric names via a raw scrape of `http://<host>:2004/metrics` after upgrades.*
