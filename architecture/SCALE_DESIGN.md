# Neo4j Scale Design — Enterprise IT Dependency Graph

Production architecture for a Neo4j Enterprise deployment targeting **5 million component nodes** and **100 million dependency relationships**, optimized for the primary operational question:

> If service X fails, which applications, databases, teams, and customers are impacted?

This document uses specific cardinalities, cost models, and trade-offs suitable for capacity planning, HA design, and DBA review.

---

## Overview

| Dimension | Target |
|---|---|
| Component nodes (abstract + concrete labels) | ~5,000,000 |
| Dependency-class relationships | ~100,000,000 |
| Primary latency SLO (blast radius, P90, warm cache) | ~500 ms |
| Hottest path (tier-1 precomputed) | ~1–5 ms property read |

**Design north star:** Index-anchored entry, bounded/APOC-controlled expansion for the dependency DAG, and **batched** fan-out over the 50M-edge customer subscription graph so no single transaction materializes the entire blast radius in heap.

---

## Graph Model at Scale

### Node types and expected cardinality

| Label / concept | Cardinality | Role |
|---|---|---|
| `:Component` (abstract / multi-label base) | ~5,000,000 | Shared identity surface for infra entities |
| `:Application` | ~500,000 | Business-facing apps |
| `:Service` | ~2,000,000 | Runtime services (blast-radius entry point) |
| `:Database` | ~200,000 | Datastores |
| `:Server` | ~300,000 | Hosts / VMs |
| `:NetworkDevice` | ~2,000,000 | Switches, load balancers, firewalls, etc. |
| `:Team` | ~50,000 | Owning org units |
| `:Customer` | ~10,000,000 | Subscribers / tenants |
| `:Incident` | ~1,000,000 | Historical + open incidents |

**Trade-off — multi-label vs separate graphs:** Putting Application/Service/Database/… under a shared `:Component` identity enables cross-type indexes and unified search, at the cost of careful label discipline in Cypher (`MATCH (c:Service)` not bare `:Component` for hot paths).

### Key relationships and expected cardinality

| Type | Cardinality | Notes |
|---|---|---|
| `:DEPENDS_ON` | ~80,000,000 | Primary dependency DAG (app→service→service→db, etc.) |
| `:HOSTED_ON` | ~5,000,000 | Placement edges (db/service → server) |
| `:SUBSCRIBED_TO` (Customer→Application) | ~50,000,000 | Customer impact fan-out (memory-dangerous if unbounded) |
| `:OWNS` (Team→Application) | ~500,000 | Org ownership for notification routing |

Other edges (e.g. Incident `AFFECTS` Application) remain comparatively sparse relative to DEPENDS_ON / SUBSCRIBED_TO.

### Why `EXTENDS` is not `DEPENDS_ON`

Self-referencing product lineage — `:Application-[:EXTENDS]->:Application` — models **inheritance / specialization** (white-label base app, versioned product line), not runtime failure coupling.

| Concern | If folded into `DEPENDS_ON` | With dedicated `EXTENDS` |
|---|---|---|
| Blast-radius semantics | Extending an app would incorrectly imply runtime outage coupling | Inbound `DEPENDS_ON` traversals stay failure-accurate |
| Traversal filters | Must exclude EXTENDS with awkward WHERE on properties | `relationshipFilter: 'DEPENDS_ON<'` (or outbound) ignores EXTENDS by type |
| Cardinality / planner | Mixes sparse lineage with dense runtime deps | Separate stats; no pollution of DEPENDS_ON degree distributions |
| Authorization | Harder to grant “see lineage” without “see ops deps” | Privilege/relationship-type separation |

**Decision:** Keep `EXTENDS` as its own type. Blast-radius Cypher never expands `EXTENDS` unless a product-line impact report explicitly requests it.

---

## Index Strategy at Scale

At 5M nodes, every hot entry point must be an **index seek**, not a label scan. Bulk import creates uniqueness after load (see Ingestion).

### Uniqueness constraints (8 entry-point keys)

Create uniqueness (backing indexes) for all stable business IDs used in CDC / APIs — e.g.:

1. `Application.applicationId`  
2. `Service.serviceId`  
3. `Database.databaseId`  
4. `Server.serverId`  
5. `NetworkDevice.deviceId`  
6. `Team.teamId`  
7. `Customer.customerId`  
8. `Incident.incidentId`  

**Why eight (and not “index everything”):** Uniqueness prevents duplicate hubs during parallel Kafka ingest (MERGE races collapse to one node). Extra unique constraints on low-selectivity properties waste write amplification without helping seeks.

### Range indexes for blast-radius partitioning

```cypher
CREATE RANGE INDEX service_tier IF NOT EXISTS FOR (s:Service) ON (s.tier);
CREATE RANGE INDEX service_environment IF NOT EXISTS FOR (s:Service) ON (s.environment);
```

**Trade-off:** Filtering `tier = 1` / `environment = 'prod'` before expansion shrinks the candidate set for scheduled pre-compute and ops dashboards. These are not substitutes for `serviceId` seeks on the primary path.

### Composite index for incident dashboards

```cypher
CREATE RANGE INDEX incident_severity_status IF NOT EXISTS
FOR (i:Incident) ON (i.severity, i.status);
```

Supports “open P1s” style filters without two single-property index intersections when both predicates are present.

### Full-text index for search-as-you-type

```cypher
CREATE FULLTEXT INDEX component_name_fts IF NOT EXISTS
FOR (c:Component) ON EACH [c.name];
```

**Trade-off:** Full-text is for UX search, not blast-radius. Do not use FTS as the entry to failure analysis (token ambiguity, lower selectivity than IDs).

### Vector index for semantic similarity (Neo4j 5.15+)

```cypher
CREATE VECTOR INDEX component_desc_embedding IF NOT EXISTS
FOR (c:Component) ON (c.descriptionEmbedding)
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 768,
    `vector.similarity_function`: 'cosine'
  }
};
```

**Trade-off:** Enables “find similar services” for incident correlation; adds storage and index build cost. Keep embeddings off the critical blast-radius path.

---

## The Blast Radius Query

Production pattern for: given `serviceId`, return impacted applications (and optionally teams/customers) without exploding heap on 50M `SUBSCRIBED_TO` edges.

```cypher
// ---------------------------------------------------------------------------
// Blast radius for Service $serviceId
// Entry: unique index seek on Service.serviceId  →  O(log n)
// Expand: APOC inbound DEPENDS_ON subgraph (bounded maxLevel)
// Customers: CALL {} IN TRANSACTIONS — never hold 50M edges in one tx
// Pagination: SKIP/LIMIT on application page
// P90 target (warm page cache, typical fan-out): ~500 ms
// ---------------------------------------------------------------------------

// :param serviceId => 'SVC-AUTH-001'
// :param pageSkip => 0
// :param pageLimit => 100
// :param includeCustomers => true

MATCH (s:Service {serviceId: $serviceId})   // NodeUniqueIndexSeek / NodeIndexSeek
CALL apoc.path.subgraphNodes(s, {
  relationshipFilter: '<DEPENDS_ON',        // INBOUND: who depends on me?
  labelFilter: '>Application|/Service',     // collect apps; walk through services
  maxLevel: 6,                              // architecture depth budget — never unbounded *
  bfs: true
})
YIELD node AS n
WITH s, [x IN collect(DISTINCT n) WHERE x:Application | x] AS apps
WITH s, apps
UNWIND apps AS app
WITH s, app
ORDER BY app.applicationId
SKIP $pageSkip LIMIT $pageLimit            // pagination guard on app result set

OPTIONAL MATCH (t:Team)-[:OWNS]->(app)
WITH s, app, collect(DISTINCT t.teamId) AS teamIds

CALL {
  WITH app
  // Batched customer aggregation — critical at 50M SUBSCRIBED_TO edges
  CALL {
    WITH app
    MATCH (c:Customer)-[:SUBSCRIBED_TO]->(app)
    RETURN count(DISTINCT c) AS customerCount
  } IN TRANSACTIONS OF 10000 ROWS
  RETURN customerCount
}

RETURN s.serviceId AS failedService,
       app.applicationId AS applicationId,
       app.name AS applicationName,
       teamIds,
       customerCount
ORDER BY applicationId;
```

### Annotation summary

| Technique | Why |
|---|---|
| Map predicate on `serviceId` | Forces **O(log n)** seek; never `MATCH (s:Service) WHERE …` alone at 2M services |
| `apoc.path.subgraphNodes` + inbound `DEPENDS_ON` | Distinct impacted node set without enumerating every path; `maxLevel` caps fan-out |
| `DISTINCT` at aggregation boundaries | Prevents duplicate apps/teams from multi-path dependency diamonds |
| `CALL { } IN TRANSACTIONS` for customers | 50M subscription edges cannot be held in one transaction memory budget |
| `SKIP` / `LIMIT` | UI/API pagination; protects response size and heap |
| ~500 ms P90 | Assumes warm page cache (store in RAM), APOC prune, and page size ~100 apps |

**Trade-off:** Pure Cypher `*` var-length is rejected at this scale (exponential paths). APOC subgraph + batching is the production default; `shortestPath` is insufficient when the deliverable is an **impact set**, not one path.

---

## Pre-computation Strategy

For **tier-1** services (highest blast radius / revenue criticality):

### Kubernetes CronJob (every 6 hours)

1. Query all `Service` where `tier = 1` (range index).  
2. For each, run the blast-radius computation (apps + customer counts) on an **analytics read replica**.  
3. Write results back to the primary as properties:

```cypher
MATCH (s:Service {serviceId: $serviceId})
SET s.blast_radius_app_ids = $appIds,
    s.blast_radius_customer_count = $customerCount,
    s.blast_radius_computed_at = datetime()
```

### Hot-path read

```cypher
MATCH (s:Service {serviceId: $serviceId})
RETURN s.blast_radius_app_ids AS apps,
       s.blast_radius_customer_count AS customers,
       s.blast_radius_computed_at AS asOf;
```

| Path | Latency | Freshness | When to use |
|---|---|---|---|
| Live blast-radius query | ~500 ms P90 | Real-time | Ad-hoc / post-change validation |
| Precomputed properties | ~1–5 ms | Up to 6h stale | Incident commander UI, paging, tier-1 dashboards |

**Trade-off:** Accept bounded staleness on the hottest path in exchange for millisecond lookups under pager load. Trigger an out-of-band recompute on major topology publishes (CDC “dependency.updated” for tier-1 neighbors).

---

## Ingestion Strategy

### Phase 1 — Initial load (5M nodes, 100M edges)

| Step | Detail |
|---|---|
| Tool | `neo4j-admin database import` (offline bulk) |
| Format | CSV nodes + relationships with header files |
| Parallelism | `--processors=N` with **N = cores − 1** (leave one core for OS/IO) |
| Indexes | **Do not** create constraints/indexes during import — add **after** load (~10× faster import) |
| Expected time | ~**2 hours** for ~100M relationships on appropriately sized hardware (SSD, 64 GB+ RAM host) |

**Trade-off:** Offline import blocks that database during load; acceptable for greenfield. Online MERGE of 100M edges would take far longer and thrash the page cache.

### Phase 2 — Real-time CDC

| Concern | Choice |
|---|---|
| Transport | Kafka topic per entity type (`component.created`, `dependency.updated`, …) |
| Connector | Kafka Connect **Neo4j Sink** |
| Batch size | **10,000** records per transaction (balance commit overhead vs lock duration) |
| Parallelism | Partition by **node label** / ID namespace to reduce write contention on the same dense hubs |
| Idempotency | Every message uses `MERGE` on unique IDs (the 8 uniqueness constraints) |

**Trade-off:** Larger batches raise throughput but increase rollback cost on failure; 10K is a proven middle ground for Neo4j write txs at this density.

### Phase 3 — Incremental refreshes

- **Daily** reconciliation: CMDB / source-of-truth vs graph; apply diffs only.  
- Large updates via:

```cypher
CALL apoc.periodic.iterate(
  'UNWIND $rows AS row RETURN row',
  'MERGE (s:Service {serviceId: row.id}) SET s += row.props',
  {batchSize: 10000, parallel: true, params: {rows: $rows}}
);
```

**Trade-off:** CDC is eventually consistent; daily reconcile closes gaps from missed events without full re-import.

---

## Capacity Planning

### On-disk store estimates

| Store | Formula | Estimate |
|---|---|---|
| Node store | ~500 bytes/node × 5M | ~2.5 GB |
| Relationship store | ~34 bytes/rel × 100M | ~3.4 GB |
| Property store | ~2 KB/node × 5M (avg) | ~10 GB |
| String store (names, etc.) | ~100 bytes × 5M | ~500 MB |
| **Total store (order of magnitude)** | | **~20–25 GB** |

Indexes, vector embeddings, and tx logs add headroom — plan **≥ 2×** raw store for growth + logs + backups staging.

### RAM sizing (minimum production primary)

| Pool | Size | Rationale |
|---|---|---|
| Page cache | **32 GB** | Hold the **entire** ~20–25 GB store (+ indexes) in memory for OLTP seek/expand |
| Heap | **16 GB** | Blast-radius aggregations / collects; keep initial == max |
| OS / page cache file / other | **16 GB** | Kernel, connectors, monitoring |
| **Minimum server** | **64 GB RAM** | |

**Trade-off:** Undersizing page cache below working set is the fastest way to turn 500 ms queries into multi-second disk-bound traversals (see metrics catalog hit-ratio alerts).

### CPU recommendation

| Role | CPU | Reasoning |
|---|---|---|
| **Primary (Raft leader / writer)** | 16+ cores (modern x86/ARM) | CDC MERGE, constraint checks, checkpoint I/O; avoid stealing cycles for analytics |
| **Read replica (app reads)** | 8–16 cores | Bolt read routing; lighter than primary if writes dominate |
| **Analytics read replica** | 16+ cores, high single-thread turbo | APOC subgraph + customer batch jobs; isolate from OLTP p99 |
| **Backup replica** | 8 cores adequate | Throughput bound by disk/network more than CPU |

Prefer **scale reads horizontally** (replicas) over oversized primary CPUs once write path is stable.

---

## High Availability Design at Scale

### Topology: 3 Raft cores + 2 analytics read replicas + 1 backup replica

```
                    ┌─────────────────────────────┐
                    │   Bolt routing (neo4j://)    │
                    └─────────────┬───────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │ writes                  │ analytics reads         │ backup only
        ▼                         ▼                         ▼
 ┌──────────────┐         ┌──────────────┐         ┌──────────────────┐
 │ Core #1      │◄───────►│ Core #2      │◄───────►│ Core #3          │
 │ PRIMARY      │  Raft   │ SECONDARY    │  Raft   │ SECONDARY        │
 └──────────────┘         └──────────────┘         └──────────────────┘
        │
        ├──────────► Analytics Read Replica A  (blast-radius / reports)
        ├──────────► Analytics Read Replica B  (pre-compute CronJobs)
        └──────────► Backup Read Replica C     (neo4j-admin backup only)
```

| Role | Count | Purpose |
|---|---|---|
| Raft core (primary + 2 secondaries) | **3** | Quorum; survive one core failure without losing majority |
| Analytics read replicas | **2** | Blast-radius reports, pre-compute CronJobs; isolate heavy CPU from Raft |
| Backup read replica | **1** | `neo4j-admin database backup` without I/O contention on cores or analytics |

Interactive API reads may share the analytics replicas under light load; under pager/incident load, pin pre-compute to one replica and interactive reads to the other.

### Routing policy

| Traffic | Route | Guardrail |
|---|---|---|
| Writes / MERGE / CDC | Bolt routing → **primary** | Never write on replicas |
| Interactive / analytics reads | Load-balanced across **2 analytics read replicas** | Short timeouts; retry on `SessionExpired` |
| Heavy reports / pre-compute | Prefer a **dedicated analytics replica** | Circuit breaker: open if p95 > SLO; shed to queue, don’t spill to primary |
| Backups | **Backup replica only** | Never run full backups against the Raft primary |

**Trade-off:** Extra replicas cost RAM/license but protect Raft latency. Mixing analytics or backup I/O on the primary is the most common cause of write-path p99 regressions at this scale.

---

## Security at Scale

### Database-level isolation

Run **separate databases** on the same Enterprise cluster:

- `prod` — live operational graph  
- `staging` — candidate topology / migration rehearsal  
- `analytics` — optional projected or replicated subset for heavy jobs  

**Trade-off:** Same cluster hardware with logical isolation beats separate clusters for cost; still enforce RBAC so staging credentials cannot touch `prod`.

### Fine-grained property access

Expose only non-sensitive Service fields to viewer roles:

```cypher
GRANT MATCH {name, serviceId, tier} ON GRAPH prod NODES Service TO team_viewer;
```

Omit secrets, internal runbooks URLs, or PII-bearing properties from the grant set.

### Multi-tenant / row-level simulation

Neo4j does not provide classic RDBMS RLS; enforce tenancy in Cypher via ownership:

```cypher
MATCH (me:User {userId: $userId})-[:MEMBER_OF]->(t:Team)-[:OWNS]->(a:Application)
MATCH path = (a)-[:DEPENDS_ON*1..4]->(x)
RETURN path;
```

**Trade-off:** Application-layer filters are mandatory; never return unscoped `MATCH (a:Application)` to tenant users.

### Encryption

| Surface | Control |
|---|---|
| Bolt | **TLS 1.3** for all clients (drivers, cypher-shell, Connect) |
| Backups | S3 (or equivalent) **SSE-KMS / encryption at rest**; no plaintext dump buckets |
| In transit to object storage | HTTPS only |

---

## Summary trade-offs

| Decision | Chosen approach | Rejected alternative | Why |
|---|---|---|---|
| Runtime vs lineage edges | Separate `EXTENDS` | Encode as `DEPENDS_ON` | Blast-radius correctness |
| Customer fan-out | `CALL {} IN TRANSACTIONS` | Single huge MATCH | Heap / tx memory |
| Tier-1 UX | 6h pre-compute properties | Always live 500 ms query | Pager / UI latency |
| Initial load | Offline admin import | Online MERGE of 100M | Time-to-live graph |
| Analytics | Dedicated read replicas | Run on primary | Protect write p99 |
| Page cache | ≥ entire store (32 GB) | Small cache + disk | Hit ratio / SLO |

---

*Document version aligned with Neo4j 5.23 Enterprise assessment stack (`architecture/SCALE_DESIGN.md`).*
