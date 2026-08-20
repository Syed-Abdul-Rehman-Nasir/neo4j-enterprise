# Neo4j Query Tuning Notes

Professional performance reference for Neo4j 5.x Enterprise (assessment environment: 5.23). Companion to `explain_profile_analysis.cypher`.

**Dev baseline in this repo** (`docker-compose.yml`): heap initial 2g / max 4g, pagecache 2g, query log INFO @ 2000ms. Those values are for local development only — size production from the formulas below.

---

## 1. Memory Configuration Reference

### `server.memory.pagecache.size`

The page cache holds store pages (nodes, relationships, properties, indexes) in OS-mapped/off-heap memory so hot data is served without disk I/O.

**Sizing formula**

\[
\text{pagecache.size} \approx 50\%\text{–}60\% \text{ of host RAM available to Neo4j}
\]

Reserve the remainder for: JVM heap, OS file cache / kernel, other processes on the host, and headroom for spikes. On a dedicated Neo4j host with 64 GB RAM, a common starting point is ~32–38 GB page cache after leaving 8–16 GB for heap and OS.

**Working set size**

The working set is the set of store pages touched by steady-state OLTP (plus index pages for those lookups). Estimate it by:

1. Measuring on-disk store + index size for active databases (`data/databases/<db>/` and related index stores).
2. Profiling which labels/relationship types dominate production traffic.
3. Observing page cache usage metrics under load until hit ratio stabilizes.

If active data + hot indexes ≪ cache, hit ratio stays high. If working set ≫ cache, the cache becomes a revolving door.

**When working set exceeds cache**

Pages are evicted and re-read from disk continuously (**disk thrashing**): latency spikes, CPU waits on I/O, and query times become I/O-bound rather than CPU-bound. Symptoms: falling hit ratio, rising page faults / disk reads, and PROFILE showing high DbHits with long wall time.

**Monitoring hit ratio**

- Metric: `neo4j.db.page_cache.hit_ratio` (Prometheus endpoint on this stack: port 2004).
- Also watch page cache evictions / faults alongside hit ratio.
- Target bands are covered in Section 3.

```ini
# neo4j.conf (or equivalent env NEO4J_server_memory_pagecache__size)
server.memory.pagecache.size=32g
```

### `server.memory.heap.initial_size` and `server.memory.heap.max_size`

Heap holds the JVM runtime: query execution state, transaction state that lives on-heap, caches that are heap-backed, and Neo4j internals.

**Keep initial == max**

Set `initial_size` and `max_size` to the **same** value. Growing the heap at runtime triggers JVM heap-resize / GC work and pause jitter. Equal sizes force a single allocation at startup and stable GC behavior.

**Max recommendation (8–16 GB)**

For most OLTP Neo4j deployments, heap in the **8–16 GB** range is the practical sweet spot:

- Enough room for concurrent query/tx state.
- Beyond ~16 GB, full GC pause times often increase (larger heaps → longer stop-the-world or longer concurrent GC cycles under pressure), which shows up as tail-latency spikes.

Prefer giving spare RAM to **page cache**, not an oversized heap.

**Relationship to query memory**

Heap is the pool; per-query and per-transaction limits (below) carve safe slices so one runaway aggregation cannot exhaust the JVM. Large `COLLECT`, sorts, and hash joins allocate against query/tx memory budgets that ultimately pressure the heap.

```ini
server.memory.heap.initial_size=8g
server.memory.heap.max_size=8g
```

### `dbms.memory.transaction.total.max`

Caps the **aggregate** memory all transactions may hold at once. When the limit is reached, new allocations fail fast instead of driving the process to OOM.

Use this as a cluster-wide safety rail: size below heap max with headroom for non-tx heap usage.

```ini
dbms.memory.transaction.total.max=2g
```

### `dbms.memory.transaction.max` / `dbms.query.memory.max` (per-query)

Per-query (and related transaction) memory limits bound a single statement’s tracked allocations (sorts, aggregations, buffers). A miswritten unbounded collect or Cartesian product hits the limit and aborts rather than taking down the instance.

```ini
# Neo4j 5.x naming — confirm exact key for your patch level
dbms.memory.transaction.max=512m
# Per-query ceiling where supported / configured in your edition:
# dbms.query.memory.max=512m
```

**Practical layering:** pagecache (working set) → heap (equal initial/max) → transaction total max → per-query max.

---

## 2. Index Strategy Decision Table

| Scenario | Index Type | Cypher to Create | When to Use |
|---|---|---|---|
| Unique lookup by business key | Uniqueness constraint (backing index) | `CREATE CONSTRAINT employee_employeeId IF NOT EXISTS FOR (e:Employee) REQUIRE e.employeeId IS UNIQUE;` | Exact match entry points (`MATCH (e:Employee {employeeId: $id})`). Enforces integrity and enables `NodeIndexSeek`. |
| Range / inequality filter | RANGE index | `CREATE RANGE INDEX incident_ts IF NOT EXISTS FOR (i:Incident) ON (i.ts);` | `WHERE` with `>`, `<`, `>=`, `<=`, `IN` lists, or equality on non-unique properties (severity, status, region, tier). |
| Full-text search | FULLTEXT index | `CREATE FULLTEXT INDEX app_name_fts IF NOT EXISTS FOR (a:Application) ON EACH [a.name, a.description];` | Tokenized / fuzzy / multi-property text search via `db.index.fulltext.queryNodes`. Not a substitute for unique ID lookups. |
| Multi-property filter | Composite RANGE index | `CREATE RANGE INDEX incident_severity_status IF NOT EXISTS FOR (i:Incident) ON (i.severity, i.status);` | Queries that filter on **both** properties together (leftmost prefix matters). Prefer over two single-property indexes when the pair is always queried together. |
| Vector similarity | VECTOR index | See example below | kNN / semantic similarity over embedding properties (GenAI / search). Requires fixed dimensions and a chosen similarity function. |

```cypher
CREATE VECTOR INDEX app_embedding IF NOT EXISTS
FOR (a:Application) ON (a.embedding)
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 768,
    `vector.similarity_function`: 'cosine'
  }
};
```

**Notes**

- Uniqueness constraints already create a backing index — do not create a redundant RANGE index on the same single unique property.
- After schema changes, verify online state: `SHOW INDEXES YIELD name, type, state, populationPercent`.
- Confirm seeks with `EXPLAIN` / `PROFILE` (`NodeIndexSeek` vs `NodeByLabelScan`).

---

## 3. The Page Cache Hit Ratio

### Targets

| Workload | Target hit ratio |
|---|---|
| OLTP (interactive, indexed lookups) | **> 99%** |
| Analytics / reporting / batch traversals | **> 95%** |

Sustained drops below target mean the working set is missing the cache or cold pages are being forced in.

### What causes drops

- **New data import / bulk load** — large sequential writes bring cold pages; caches churn.
- **Index population** — background index builders read/write large portions of store and index files.
- **Reporting query cold start** — first scan of rarely touched labels/relationships after restart or cache eviction.
- **Insufficient `pagecache.size`** — working set permanently larger than cache → chronic thrashing.

### How to investigate

1. Plot `neo4j.db.page_cache.hit_ratio` (and faults/evictions) around the incident window.
2. Correlate with query log spikes (`executionTimeMs`) and heavy `PROFILE` DbHits.
3. Run `SHOW INDEXES YIELD name, type, state, populationPercent, failureMessage` — population in progress often explains temporary hit-ratio dips.
4. Check whether analytics jobs run on the same members as OLTP.

### Recovery

1. **Kill or cancel** pathological heavy queries / transactions consuming I/O.
2. **Offload analytics** to a **read replica** (or separate reporting database) so OLTP page cache stays hot.
3. **Increase `server.memory.pagecache.size`** after confirming RAM headroom (do not steal from an already-tight heap without rebalancing).
4. Warm critical entry-point indexes with representative lookups after maintenance windows.

---

## 4. Query Log Analysis

### How to enable

```ini
db.logs.query.enabled=INFO
db.logs.query.threshold=2s
```

In this project’s Compose file these map to `NEO4J_db_logs_query_enabled=INFO` and `NEO4J_db_logs_query_threshold=2000ms` — statements slower than the threshold are logged.

Use `VERBOSE` temporarily when you need parameter values and richer planner detail in non-prod.

### What to look for in the log

| Field | Meaning | Red flag |
|---|---|---|
| `executionTimeMs` | Wall time for the statement | Rising p95/p99; outliers after deploys |
| `allocatedBytes` | Memory tracked for the query | Sudden jumps → large collects/sorts/products |
| `plannedRows` vs `actualRows` | Planner estimate vs runtime cardinality | Systematic large gaps |

Also note page hits/faults when present, and whether the plan used index seeks.

### Pattern: `actualRows >> plannedRows`

The planner’s **cardinality estimate is wrong**. Downstream operators (Expand, Filter, EagerAggregation) were costed for a tiny input and then flooded.

Common causes: stale statistics after large imports, new indexes/constraints not reflected in cached plans, or highly skewed property distributions.

**After schema changes** (new indexes/constraints, major data loads):

```cypher
CALL db.clearQueryCaches();
```

Re-`EXPLAIN`/`PROFILE` critical queries. If estimates remain poor, revisit index design and predicates (indexable equality first, selective filters early, avoid Cartesian products).

---

## 5. Anti-Patterns Reference

### 1. `MATCH (n) WHERE n.prop = 'value'` with no index on `prop`

**Why it hurts:** Planner typically chooses `NodeByLabelScan` + `Filter` — O(n) in label size; DbHits scale with every node property check.

**Fix:** Create a UNIQUE constraint or RANGE index on `prop`, then write `MATCH (n:Label {prop: $value})` (or ensure the WHERE form is index-backed). Confirm `NodeIndexSeek` in EXPLAIN.

### 2. `MATCH (a)-[*]->(b)` (unbounded traversal)

**Why it hurts:** Explores paths of arbitrary length; exponential fan-out and cycle risk; transaction timeouts and memory blowups.

**Fix:** Always bound depth: `[*1..4]` (or architecture-appropriate N). Prefer `shortestPath` with a bound when only one path is needed. See `explain_profile_analysis.cypher` Sections 5 and 8.

### 3. Multiple disconnected `MATCH` clauses (Cartesian product)

**Why it hurts:** Independent pipelines are multiplied (`CartesianProduct`) before a later join predicate applies — rows explode.

**Fix:** Start from one indexed anchor; keep patterns connected; pass variables with `WITH`; use correlated `CALL { WITH x MATCH ... }` so the inner match cannot freestand.

### 4. `COLLECT` then `SIZE` instead of `COUNT(DISTINCT …)`

**Why it hurts:** Materializes a full list in memory only to measure length — higher `allocatedBytes` and Eager buffers.

**Fix:** Use `count(*)` / `count(DISTINCT e)` for cardinalities. Reserve `collect()` for when the caller needs the list contents.

### 5. `RETURN *` on large traversals

**Why it hurts:** Ships every bound node, relationship, and path property to the client — network and serialization dominate; hides accidental variable retention.

**Fix:** Project only required fields (`RETURN a.name, s.name, db.name`). Drop unused variables with `WITH` before return.

### 6. Property used for relationship-type discrimination

**Why it hurts:** Modeling `[:RELATED {type:'USES'}]` forces scanning a broad relationship type then filtering on a property — poor selectivity vs native types.

**Fix:** Use distinct relationship types (`:USES`, `:DEPENDS_ON`, `:READS_FROM`). Filter with type in the pattern: `MATCH (e)-[:USES]->(a)`.

---

## 6. Production Query Guard Checklist

- [ ] All entry-point node lookups use indexed properties
- [ ] All variable-length traversals have explicit depth limits
- [ ] LIMIT applied where result sets could be large
- [ ] Parameters used (not string concatenation)
- [ ] Transaction timeout configured
- [ ] Query tested with PROFILE on production-sized data before deployment

---

*End of reference. Pair EXPLAIN (plan shape) with PROFILE (Rows / DbHits / memory) before promoting any Cypher change.*
