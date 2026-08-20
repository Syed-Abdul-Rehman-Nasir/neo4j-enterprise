# Neo4j Production Troubleshooting Runbook

Incident response reference for Neo4j Enterprise 5.x (assessment stack: 5.23). Execute steps **in order**. Do not skip Step 1 — identifying and killing runaway queries usually restores service in under a minute.

> Neo4j 5 also exposes `SHOW QUERIES` / `SHOW TRANSACTIONS` as alternatives to some `CALL dbms.*` procedures below. Prefer the commands in this runbook for consistency; either form is valid when privileges allow.

---

## Scenario: CPU 95% / Memory 90% / Queries 20–30s / Timeouts / Disk Growing

**Symptoms**

- Host or container CPU near saturation (~95%)
- Memory / heap pressure (~90%)
- Application queries taking 20–30 seconds or timing out
- Data volume or transaction-log disk usage growing unexpectedly

**Goal:** Restore latency, protect the cluster, then fix root cause (bad Cypher vs infrastructure).

---

## Triage Order

### Step 1: Identify runaway queries (first action, &lt;30 seconds)

**Command**

```cypher
CALL dbms.listQueries()
YIELD queryId, query, elapsedTimeMillis, allocatedBytes, status
ORDER BY elapsedTimeMillis DESC
LIMIT 10;
```

**What to look for**

- `elapsedTimeMillis > 10000` (query running longer than 10 seconds)
- `allocatedBytes > 500000000` (~500 MB) — memory hog / Cartesian or large collect

**Decision**

1. **Copy the `query` text and `queryId` into the incident ticket** (document before killing).
2. If a runaway is confirmed:

```cypher
CALL dbms.killQuery($queryId);
```

Example:

```cypher
CALL dbms.killQuery('query-1234');
```

**Expected outcome**

CPU should drop within seconds if a CPU-bound query was the cause. Re-check application latency. If CPU remains high, continue to Step 2.

---

### Step 2: Inspect open transactions

**Command**

```cypher
CALL dbms.listTransactions()
YIELD transactionId, currentQueryId, status, elapsedTimeMillis, allocatedBytes
WHERE elapsedTimeMillis > 30000;
```

**What to look for**

- `status = 'BLOCKED'` — lock contention; a writer or long reader is holding locks
- Very large `allocatedBytes` — transaction state ballooning toward OOM

**Decision**

Kill stale or blocked transactions after documenting `transactionId` / associated query:

```cypher
CALL dbms.killTransaction($transactionId);
```

**Expected outcome**

Locks release; blocked OLTP traffic resumes. If many transactions are uniformly slow (not one stuck tx), suspect infrastructure — jump to the signature section after a quick Step 3–5 pass.

---

### Step 3: Check query plans for missing indexes

**Commands**

1. Take the **top 3 slowest queries** from Step 1 (documented text).
2. For each, run `EXPLAIN` (does not execute; safe under load):

```cypher
EXPLAIN
<paste query here>;
```

**What to look for**

- `NodeByLabelScan` on a large label where the query filters by property — missing or unused index
- Prefer seeing `NodeIndexSeek` / `NodeUniqueIndexSeek` on entry-point predicates

**Fix**

Create the missing index/constraint (adjust label/property to match the plan):

```cypher
CREATE RANGE INDEX incident_status IF NOT EXISTS
FOR (i:Incident) ON (i.status);
```

New queries can use the index as soon as the planner sees it; **population runs in the background**.

**Verify population**

```cypher
SHOW INDEXES
YIELD name, state
WHERE state = 'POPULATING';
```

Wait until state is `ONLINE` before closing the incident on “missing index” alone.

---

### Step 4: Check JVM heap pressure

**Command**

```cypher
CALL dbms.listConfig()
YIELD name, value
WHERE name CONTAINS 'heap';
```

Confirm `server.memory.heap.initial_size` and `server.memory.heap.max_size` (should be equal in production).

**Metrics to check in Datadog**

- `neo4j.jvm.memory.heap.used` vs `neo4j.jvm.memory.heap.max`
- **Threshold concern:** heap **> 85% used** → GC thrashing likely (latency cliffs, CPU spent in GC)

**Check logs**

```bash
grep "GC" /var/log/neo4j/debug.log | tail -50
```

Look for frequent full GC, long pause times, or allocation-failure messages.

**Fix options**

1. Increase heap size (**requires restart**); keep initial == max; prefer giving spare RAM to page cache when possible.
2. Cap concurrent transaction memory so one tx cannot exhaust the heap:

```ini
dbms.memory.transaction.total.max=<safe-limit>
```

(Example: `2g` on an 8g heap — size to your capacity plan.)

---

### Step 5: Evaluate page cache hit ratio

**Command**

```cypher
CALL dbms.queryJmx('org.neo4j:instance=kernel#0,name=Page cache')
YIELD attributes
RETURN attributes;
```

Also monitor Datadog / Prometheus: `neo4j.db.page_cache.hit_ratio`.

**Threshold**

- **&lt; 95%** → working set likely exceeds page cache (disk-bound traversals)

**Fix**

Short-term — refresh planner caches after schema/stats changes:

```cypher
CALL dbms.clearQueryCaches();
```

Long-term — increase `server.memory.pagecache.size` (typically ~50–60% of host RAM on a dedicated Neo4j host) and restart if required by your deployment process.

**Impact**

Low cache hit ratio means graph traversals read from disk → latency spikes even for “simple” indexed queries under concurrency.

---

### Step 6: Diagnose disk growth

**Commands**

```bash
# Store files (nodes, relationships, properties, indexes)
ls -lh $NEO4J_HOME/data/databases/

# Transaction logs
ls -lh $NEO4J_HOME/data/transactions/
```

Inspect which path is growing and how fast (`du -sh` over time if needed).

**Cause A: Transaction log accumulation**

Logs accumulate if checkpoints are delayed. Trigger a checkpoint:

```cypher
CALL db.checkpoint();
```

**Cause B: Missing / failed backup**

Transaction logs are often pruned only after a successful backup checkpoint. Verify backup job health (`admin/backup.sh`, cron, Datadog backup events). Re-run a successful full backup if backups have been failing.

**Cause C: Query log verbosity**

Verbose query logging can fill disk under load. Review:

```ini
db.logs.query.enabled
db.logs.query.threshold
```

Consider **increasing** the threshold (e.g. only log queries slower than 2s) so routine fast queries are not written to disk.

---

## Distinguishing Bad Cypher vs Infrastructure Problems

### Bad Cypher signature

| Signal | Detail |
|---|---|
| PROFILE | High **DbHits** on specific operators (`NodeByLabelScan`, unbounded `VarLengthExpand`, `CartesianProduct`) |
| Scope | Problem is **query-specific** — some endpoints fast, one path slow |
| Metrics | CPU spike **correlates exactly** with that query’s execution window |
| Fix | Query optimization / indexes — **not** server hardware changes |

See also: `cypher/performance/explain_profile_analysis.cypher` and `query_tuning_notes.md`.

### Infrastructure signature

| Signal | Detail |
|---|---|
| Scope | **ALL** queries slow, uniformly |
| OS | Disk I/O wait **> 20%**; elevated network latency to cluster peers |
| Neo4j | Page cache hit ratio drops across databases; JVM GC frequency rises |
| Cluster | Replication lag; leader election events in `debug.log` |
| Fix | Hardware scaling, pagecache/heap sizing, cluster configuration — **not** Cypher tweaks alone |

---

## Post-Incident Checklist

After every **P1** or **P2** incident:

- [ ] Root cause identified and documented
- [ ] Problematic query fixed and deployed
- [ ] Missing index added if applicable
- [ ] Query log reviewed for similar slow queries
- [ ] Datadog alert threshold adjusted if needed
- [ ] Runbook updated with new finding

---

*End of runbook. When in doubt: kill runaway queries first, restore service, then prove Cypher vs infrastructure with PROFILE + OS/Neo4j metrics before changing cluster sizing.*
