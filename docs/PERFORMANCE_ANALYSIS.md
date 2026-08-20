# Neo4j Query Performance Analysis

## 1. How to Read a Neo4j Query Plan

### EXPLAIN vs PROFILE

- **EXPLAIN:** logical plan only, no execution, uses estimated row counts
- **PROFILE:** executes the query, returns actual row counts and DbHits
- Use EXPLAIN for plan inspection during development (no side effects)
- Use PROFILE on staging with production-representative data for tuning

### Reading direction

Plans are trees read **bottom-up**. Data flows from leaf operators (data sources)
upward through transformation operators to the final RETURN.

### Key operators and what they mean

| Operator | Meaning | Good or Bad? |
|---|---|---|
| `NodeIndexSeek` | Lookup via B-tree index on a specific value | ✅ Best case |
| `NodeIndexScan` | Scan all entries in an index | ⚠️ OK for small indexes |
| `NodeByLabelScan` | Full scan of all nodes with a label | ❌ Avoid on large graphs |
| `Expand(All)` | Traverse relationships from a node | ✅ Expected for graph traversal |
| `VarLengthExpand(Pruning)` | Variable-depth traversal with cycle detection | ✅ Better than All |
| `VarLengthExpand(All)` | Variable-depth traversal without pruning | ⚠️ Watch cardinality |
| `CartesianProduct` | Cross-join of two unconnected MATCH patterns | ❌ Almost always wrong |
| `Filter` | Post-traversal predicate check | ⚠️ Push earlier if possible |
| `EagerAggregation` | Aggregation requiring full result before proceeding | ⚠️ Memory intensive |
| `OrderedAggregation` | Aggregation on pre-sorted input | ✅ More memory-efficient |

### What to look at in PROFILE output

For each operator, PROFILE shows:

- `Rows`: actual rows produced (compare to `EstimatedRows` from EXPLAIN)
- `DbHits`: number of page cache reads. High DbHits = index missing or large scan
- `Memory`: peak memory allocated by this operator
- `Time`: wall clock time (ms)

If `Rows` >> `EstimatedRows`, the planner's cardinality estimate is wrong.
This often happens after large data imports without running `CALL db.clearQueryCaches()`.

Companion files: `cypher/performance/explain_profile_analysis.cypher`, `cypher/performance/query_tuning_notes.md`.

## 2. Q2 Employee Chain — EXPLAIN Walkthrough

Query:

```cypher
EXPLAIN
MATCH (e:Employee {employeeId: $employeeId})-[:USES]->(a:Application)
MATCH (a)-[dep:DEPENDS_ON]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name, a.name, s.name, db.name, dep.weight
ORDER BY a.name, s.name
```

Expected plan (top → bottom = output → source):

```
ProduceResults
  └── Sort (a.name, s.name)
        └── Projection (e.name, a.name, s.name, db.name, dep.weight)
              └── Expand(All) [:READS_FROM]
                    └── Expand(All) [dep:DEPENDS_ON]
                          └── Expand(All) [:USES]
                                └── NodeIndexSeek(:Employee:employeeId) ← ✅ index used
```

Key point: `NodeIndexSeek` at the leaf means we start with exactly 1 node
(the employee with that ID) and expand outward. The traversal cost is
proportional to the subgraph size, not the full dataset.

PROFILE output on sample dataset (10 employees, 5 apps, 6 services, 3 DBs):

```
Operator                      | Rows | DbHits | Notes
NodeIndexSeek(:Employee)      |    1 |      2 | One lookup, one property read
Expand(All) [:USES]           |    2 |      4 | EMP-001 uses APP-001 + APP-004
Expand(All) [dep:DEPENDS_ON]  |    4 |      6 | 2 services per app
Expand(All) [:READS_FROM]     |    4 |      4 | One DB per service
Projection                    |    4 |      8 | Read 2 props per row
Sort                          |    4 |      0 | In-memory sort (tiny dataset)
ProduceResults                |    4 |      0 |
Total DbHits: 24 — extremely efficient
```

## 3. Slow Query Anti-Pattern — EXPLAIN Walkthrough

Anti-pattern (no index anchor, label scan):

```cypher
EXPLAIN
MATCH (e:Employee)
WHERE e.role = 'CFO'
MATCH (e)-[:USES]->(a:Application)
RETURN e.name, a.name
```

Expected plan:

```
ProduceResults
  └── Projection
        └── Expand(All) [:USES]
              └── Filter (e.role = 'CFO')
                    └── NodeByLabelScan(:Employee) ← ❌ full label scan
```

Problem: NodeByLabelScan reads every Employee node, then filters by role.
At 1M employees, this scans 1M nodes to find potentially 1.
Fix: ensure `CREATE RANGE INDEX employee_role IF NOT EXISTS FOR (e:Employee) ON (e.role)` —
plan changes toward `NodeIndexSeek(:Employee:role)`.

## 4. Optimization Techniques Applied in This Project

### Technique 1 — Index anchoring

Always start MATCH from a node with a unique or indexed property.
Example: `MATCH (e:Employee {employeeId: $employeeId})` → NodeIndexSeek.
Never: `MATCH (e:Employee) WHERE e.employeeId = $employeeId` on an unindexed prop.

Q1 anchors on `Department.name` via `department_name_range` / `idx_dept_name`.

### Technique 2 — Bounded variable-length traversal

Always use explicit depth limits: `[:DEPENDS_ON*1..4]` not `[:DEPENDS_ON*]`.
Unbounded traversal on a cyclic graph = infinite loop.
Unbounded on a DAG = exponential fan-out. Worst case is O(branches^depth).

### Technique 3 — CALL {} subquery to eliminate Cartesian products

Two disconnected MATCH clauses can produce a CartesianProduct operator.
Fix: use `CALL { WITH anchor MATCH ... RETURN ... }` to pass the anchor variable.
See `cypher/performance/explain_profile_analysis.cypher` Section 8.

### Technique 4 — APOC for deep traversal

For impact analysis spanning unknown depth, `apoc.path.subgraphNodes` is
more efficient than variable-length Cypher because it uses BFS with visited
tracking, eliminating redundant path exploration.

## 5. Memory Configuration Reference

| Setting | Recommended | Effect |
|---|---|---|
| `server.memory.pagecache.size` | 50–60% of RAM | Holds graph store in memory. Higher = fewer disk reads |
| `server.memory.heap.initial_size` | Equal to max | Prevents resize pauses during JVM warmup |
| `server.memory.heap.max_size` | 8–16 GB | Beyond 16 GB, GC pause time increases significantly |
| `db.memory.transaction.total.max` | 2–4 GB | Limits total memory held by concurrent transactions |
| `db.query.memory.max` | 512 MB | Per-query memory cap — prevents one query from OOMing the JVM |

Lab Compose (`docker-compose.yml`): heap initial = max = 4g; pagecache = 2g.

### Page cache hit ratio

- Target: > 99% for OLTP
- Check: `neo4j.db.page_cache.hit_ratio` in Datadog / Prometheus
- If < 95%: working set exceeds cache. Kill analytics queries first,
  then increase `pagecache.size` or add a dedicated analytics read replica.

### Query log analysis

Enable: `db.logs.query.enabled=INFO`, `db.logs.query.threshold=2000ms`
Log shows: `executionTimeMs`, `allocatedBytes`, `plannedRows` vs `actualRows`
Key signal: if `actualRows >> plannedRows` → stale planner statistics → run
`CALL db.clearQueryCaches()` after schema or major data changes.

## 6. Query-by-Query Lab Summary

| Query | Plan | Bottleneck | Fix Applied |
|-------|------|------------|-------------|
| Q1 | NodeIndexSeek on Department.name | Was label scan | `idx_dept_name` / `department_name_range` |
| Q2 | NodeIndexSeek | None | — |
| Q3 | NodeByLabelScan + aggregation | App label scan | Acceptable at lab scale; replica at prod |
| Q4 | NodeIndexSeek + path expand | None | — |
| Q5 | NodeIndexSeek + bounded path | None (`*1..3`) | — |
| Q6 | Label scan + sort | Unstable ties | `ORDER BY unique_users DESC, applicationId ASC` |
| Q7 | Label scan + aggregation | Empty on sample | Acceptable |
| Q8 | Anti-join | Unparameterized filter | Parameterized `$asOf` |
| Q9 | NodeIndexSeek + path | None | — |
