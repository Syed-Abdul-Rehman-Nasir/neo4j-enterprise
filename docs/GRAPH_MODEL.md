# Graph Model — Modeling Decisions

Assessor-facing rationale for every major modeling choice in the **Enterprise IT Dependency Graph**. Examples cite the lab schema in `cypher/01_sample_data.cypher`, queries under `cypher/queries/`, and scale notes in `architecture/SCALE_DESIGN.md`.

---

## Section 1: Why Graph, Not Relational

### The question (Q4)

When a **database** fails, which **employees** are impacted? The path is:

```text
Database ← READS_FROM ← Service ← DEPENDS_ON ← Application ← USES ← Employee
                                                              └─ BELONGS_TO → Department
```

This is query **Q4** (`cypher/queries/q4_db_impact_analysis.cypher`): blast-radius fan-out from a single indexed `databaseId`.

### SQL: multi-table JOIN (illustrative)

In a normalized relational model the same question becomes a chain of entity tables plus junction tables:

```sql
-- Impacted employees when database_id = 'DB-001'
SELECT DISTINCT
  e.name  AS impacted_employee,
  e.email AS email,
  d.name  AS department,
  a.name  AS via_application,
  s.name  AS via_service,
  db.name AS database_name
FROM databases db
JOIN service_reads_from srf ON srf.database_id = db.database_id
JOIN services s             ON s.service_id = srf.service_id
JOIN app_depends_on ado     ON ado.service_id = s.service_id
JOIN applications a         ON a.application_id = ado.application_id
JOIN employee_uses eu       ON eu.application_id = a.application_id
JOIN employees e            ON e.employee_id = eu.employee_id
JOIN departments d          ON d.dept_id = e.dept_id
WHERE db.database_id = 'DB-001'
ORDER BY e.name;
```

That is a **six-hop logical join** across entity and bridge tables (`databases` → `service_reads_from` → `services` → `app_depends_on` → `applications` → `employee_uses` → `employees`, plus `departments`). Every new dependency hop in production (extra service tiers, shared platforms) adds another JOIN and another intermediate cardinality estimate.

### Cypher: single pattern (this repo)

```cypher
MATCH (db:Database {databaseId: $databaseId})
        <-[:READS_FROM]-(s:Service)
        <-[:DEPENDS_ON]-(a:Application)
        <-[:USES]-(e:Employee)
MATCH (e)-[:BELONGS_TO]->(d:Department)
RETURN DISTINCT e.name AS impacted_employee,
                e.email AS email,
                d.name AS department,
                a.name AS via_application,
                s.name AS via_service,
                db.name AS database_name
ORDER BY impacted_employee;
```

The topology **is** the query. Anchoring on `Database.databaseId` (uniqueness constraint → index seek) then walking typed relationships mirrors how operators think about blast radius. `DISTINCT` remains required because one employee may reach the same database via multiple app/service paths (e.g. Alice → FinanceSuite and DataLakeDash).

### Algorithmic complexity

| Model | Work model | Complexity (intuitive) |
|---|---|---|
| Relational JOIN chain | Intermediate join products grow with table sizes and selectivity of each FK match | **O(n × m × k × …)** — product of participating relation cardinalities / join fan-outs before filters prune |
| Graph traversal | From one start node, expand only along typed edges to depth *d* | **O(depth × avg_degree)** — work proportional to neighborhood explored, not full-table cross products |

- **SQL:** Even with indexes on FK columns, the planner still materializes join intermediates. As *n* (services reading a DB), *m* (apps depending on those services), and *k* (users of those apps) grow independently, cost scales with the **product** of those fan-outs across the chain—classically written **O(n×m×k)** for a three-way association product (here extended across six tables).
- **Cypher / property graph:** Start at one `Database` node (O(log N) seek). Each hop examines only adjacent relationships of the named type. For fixed architecture depth and average out/in-degree *g*, cost is **O(depth × avg_degree)** (more precisely O(sum of degrees along visited frontier)), not O(|Employees| × |Applications| × …).

**Why this domain favors graph:** impact analysis is *local connectivity*, not set-oriented reporting over the whole employee table. Graphs charge for what you touch; deep JOIN chains charge for how tables combine.

---

## Section 2: Node vs Property vs Relationship — Decision Rules

### Rule 1 — A thing is a **node** if it has its own identity and properties, and is referenced by more than one other thing

| Decision | Why |
|---|---|
| **Department is a node**, not `Employee.departmentName` | Departments have `deptId`, name, and many employees (`BELONGS_TO`). Q1 starts at Department and fans out to apps. Denormalizing the name onto every employee duplicates data and blocks “all apps used by Finance” without scanning employees. |
| **Application / Service / Database / Server** are nodes | Each has a stable business ID, multiple attributes, and many inbound/outbound references (users, dependencies, hosting, incidents). |
| **Incident is a node** | Own lifecycle, severity, status, timestamps—shared across apps via `AFFECTS` (see Section 5). |

**Anti-pattern avoided:** stuffing “Finance” as a string on every employee—cheap to write, expensive to query and clean.

### Rule 2 — A thing is a **relationship property** if it describes the connection itself, not either endpoint

| Property | Why it belongs on the edge |
|---|---|
| **`USES.since`** | “When did *this* employee start using *this* application?” Neither Employee nor Application alone owns that fact. |
| **`DEPENDS_ON.weight`** | Criticality of *this* app→service dependency (0.0–1.0). The same service can be weight `1.0` for one app and `0.6` for another. |

**Anti-pattern avoided:** putting `since` on Employee (one value for all apps) or `weight` on Service (one value for all dependents).

### Rule 3 — A thing is a **node property** if it only describes that node and is never traversed

| Property | Why it stays on the node |
|---|---|
| **`Employee.email`** | Attribute of the person; queries return it, they do not walk “through” email. |
| **`Server.ip`**, `region`, `cpu_cores` | Host inventory facts; hosting topology is the `HOSTED_ON` relationship. |
| **`Application.tier`**, `owner`, `version` | Describe the app; traversal uses `USES` / `DEPENDS_ON` / `AFFECTS`, not these fields. |

**Anti-pattern avoided:** inventing `:HAS_EMAIL` or `:HAS_IP` relationships for scalar attributes that are never path hops.

---

## Section 3: Relationship Type Choice

This project uses **named** types: `BELONGS_TO`, `USES`, `DEPENDS_ON`, `READS_FROM`, `HOSTED_ON`, `AFFECTS` (and at scale, `OWNS`, `SUBSCRIBED_TO`, `EXTENDS`). We reject a generic `CONNECTED_TO` / `RELATED_TO` catch-all.

### 1. Named types allow type-specific traversal (much faster)

Neo4j stores relationships by type. Expanding `()-[:READS_FROM]->()` only walks that type’s adjacency—not every edge on the node. A generic `CONNECTED_TO` forces property filters (`WHERE r.kind = 'reads_from'`) after denser expands, raising DbHits and planner uncertainty.

### 2. Named types make query intent explicit

```cypher
(db)<-[:READS_FROM]-(s)<-[:DEPENDS_ON]-(a)<-[:USES]-(e)
```

reads as an ops narrative. The same pattern with only `CONNECTED_TO` hides whether you meant runtime dependency, ownership, or lineage—reviewers and future maintainers cannot tell correct from accidental.

### 3. Named types prevent accidental cross-type traversals

Blast-radius queries must **not** follow product lineage the same way as runtime failure. At scale, `:Application-[:EXTENDS]->:Application` is intentionally **separate** from `DEPENDS_ON` so inbound failure analysis does not treat white-label inheritance as outage coupling (`architecture/SCALE_DESIGN.md`). With a single generic type, excluding lineage requires fragile property predicates on every query.

**Summary:** type is a first-class part of the schema contract, not a string attribute on a universal edge.

---

## Section 4: Property Graph vs RDF / Triple Store

| Concern | Property graph (Neo4j) | RDF / SPARQL triple store |
|---|---|---|
| World assumption | **Closed-world** CMDB/ops: known entities, known link types | **Open-world** ontologies: missing data ≠ false; heavy inference |
| Attributes | First-class **properties on nodes and relationships** | Typically more triples (`ex:alice ex:email "…"`) or reification for edge attributes |
| Query shape | Local pattern match / path expand (blast radius) | Graph pattern + optional reasoning over vocabularies |
| Fit for this project | High — IT dependency + incident ops | Better for shared open ontologies, semantic web integration |

This assessment models a **bounded enterprise topology** with dense, typed relationships and rich edge properties (`USES.since`, `DEPENDS_ON.weight`). Responders need millisecond-to-subsecond **traversals from a known ID**, not open-world entailment. Neo4j’s property graph matches that closed-world, relationship-centric workload; RDF/SPARQL remains appropriate when the primary problem is ontology alignment and inference across independently published vocabularies.

---

## Section 5: The Incident Model

### Why Incident is a node (not a property on Application)

An incident has:

- Stable identity (`incidentId`)
- Lifecycle fields (`severity`, `status`, `ts`, `resolvedTs`, `mttr_minutes`, `title`)
- Potential **many-to-many** linkage to applications

Stuffing “last incident severity” onto Application loses history, blocks multiple concurrent incidents, and cannot express one incident affecting several apps. A first-class `:Incident` node keeps history queryable and constraints enforceable (`Incident.incidentId` unique; severity/status existence constraints in the lab schema).

### Why direction is `(Incident)-[:AFFECTS]->(Application)`

Sample data and Q3 use **Incident → Application**:

- The **subject of the fact** is the incident (“INC-001 affects FinanceSuite”).
- One incident can `AFFECTS` multiple applications without duplicating incident properties.
- Applications accumulate **inbound** `AFFECTS` for “how many / which incidents hit this app?” (natural for trending).

The reverse (`Application)-[:AFFECTED_BY]->(Incident)`) is semantically similar but would push “subject” onto the app and make multi-app incidents awkwardly fan-out from apps. We keep incident as the authoritative node and point at impacted apps.

### What this model supports

| Use case | How the model answers it |
|---|---|
| **Impact analysis** | From Incident → apps (and onward into services/DBs via app dependencies); or from infra failure → apps → open incidents (`architecture/scale_model.cypher` impact report). |
| **MTTR calculation** | Duration lives on the Incident (`resolvedTs - ts`, or stored `mttr_minutes` in sample data)—not on the relationship. |
| **Incident trending by application** | `(a:Application)<-[:AFFECTS]-(i:Incident)` + `count(i)` / group by severity (Q3). |
| **Reopen detection** | Status transitions on the same Incident node (`resolved` → `open`), or a **new** Incident node for a recurrence while retaining historical resolved nodes—both keep Application free of overloaded scalar fields. |

---

## Section 6: Relationship Properties in Detail

### `USES.since` (Employee → Application)

- **Meaning:** when this employee’s use of this application began.
- **Type in sample data:** ISO **date string** (`'2023-01-01'`).
- **Why string for demos:** trivial to author in Cypher MERGE scripts, easy to eyeball in Browser, and sufficient for equality / lexicographic range demos without teaching temporal functions.
- **Production note:** prefer Neo4j temporal (`date` / `datetime`) for correct ordering, time-zone safety, and duration math. String is a deliberate **simplicity trade-off** for the assessment dataset, not a recommendation for production CMDB loads.

### `DEPENDS_ON.weight` (Application → Service)

- **Meaning:** criticality of this dependency in **0.0–1.0** (sample values include `1.0`, `0.8`, `0.6`).
- **Use:** prioritize impact-analysis results (fail high-weight edges first in RCA / paging severity), without inventing a separate “critical dependency” node type.
- **Why on the relationship:** criticality is pairwise—FinanceSuite may critically depend on auth-service (`1.0`) while another app only soft-depends on the same service.

### `AFFECTS` has no properties (Incident → Application)

- **Timestamps, severity, status** live on the **Incident** node (`ts`, `resolvedTs`, `severity`, `status`).
- **Why not on the edge:**
  - An incident’s open/resolved time is a property of the **event**, not of each app link. If one incident affects three apps, edge-level timestamps would triplicate the same facts and risk drift.
  - MTTR, reopen, and trending all key off incident identity and status; keeping them on the node preserves a single source of truth.
  - The edge only asserts **membership in the impact set**. Extra edge properties would be warranted only for link-specific facts (e.g. “impact percentage per app”)—which this assessment does not model.

`READS_FROM`, `HOSTED_ON`, and `BELONGS_TO` are likewise property-free in the sample graph: they are pure topology; attributes belong on the endpoints (engine/version on Database, IP on Server, etc.).

---

*This document is the conceptual companion to the executable schema and queries. For scale cardinality and HA topology, see `architecture/SCALE_DESIGN.md`.*
