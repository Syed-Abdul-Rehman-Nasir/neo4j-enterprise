// =============================================================================
// explain_profile_analysis.cypher
// Senior-level Neo4j query performance walkthrough
// Prerequisites: 00_constraints_indexes.cypher + 01_sample_data.cypher loaded
// Sample anchor: EMP-001 (Alice Mercer) → apps → services → databases
// APOC required for Section 7 (enabled via docker-compose NEO4J_PLUGINS)
// =============================================================================

// #############################################################################
// ===== SECTION 1: THE BASELINE SLOW QUERY =====
// #############################################################################
// Deliberately inefficient employee-chain traversal demonstrating three sins:
//   1) WHERE on a property after MATCH (label) instead of index-friendly map
//   2) Unbounded variable-length traversal [:DEPENDS_ON*]
//   3) Unconnected MATCH clauses that invite CartesianProduct
// #############################################################################

// ⚠️ ANTI-PATTERN: This query will full-scan in production
MATCH (e:Employee)
WHERE e.employeeId = 'EMP-001'
MATCH (db:Database)
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*]->(s:Service)-[:READS_FROM]->(db)
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       db.name AS database_name;

// #############################################################################
// ===== SECTION 2: EXPLAIN ANALYSIS =====
// #############################################################################
// EXPLAIN shows the planner's chosen operators WITHOUT executing the query.
// Use it to catch NodeByLabelScan, CartesianProduct, and unbounded expands
// before you burn CPU on PROFILE against production-sized data.
// #############################################################################

EXPLAIN
MATCH (e:Employee)
WHERE e.employeeId = 'EMP-001'
MATCH (db:Database)
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*]->(s:Service)-[:READS_FROM]->(db)
RETURN e.name, a.name, s.name, db.name;

// -----------------------------------------------------------------------------
// EXHAUSTIVE OPERATOR REFERENCE (read this against the EXPLAIN tree above)
// -----------------------------------------------------------------------------
//
// HOW TO READ THE PLAN TREE
//   Neo4j prints operators as a tree. Data flows BOTTOM-UP: leaf operators
//   produce rows; parent operators consume those rows. Arrows / nesting show
//   which child feeds which parent. Always start reading at the leaves
//   (scans/seeks), then follow upward through Expand → Filter → ProduceResults.
//
// ESTIMATED ROWS vs ACTUAL ROWS
//   EXPLAIN shows estimated rows from statistics (label counts, index
//   selectivity). PROFILE shows actual rows after execution. Large gaps
//   (estimate << actual or estimate >> actual) mean stale statistics or a
//   cardinality mis-estimate — revisit indexes and WITH/LIMIT placement.
//
// DbHits (PROFILE only)
//   Every page-cache access counts as a DbHit: reading a node, relationship,
//   property, or label from store. High DbHits with low Rows often means
//   scanning many candidates then discarding them (Filter after LabelScan).
//   Goal: fewer DbHits per useful result row.
//
// NodeByLabelScan
//   Meaning: iterate every node with a given label.
//   Why bad: O(n) in label cardinality; on millions of Employees this is a
//   full store walk before any Filter runs.
//   Triggers: MATCH (e:Employee) without an equality predicate the planner
//   can bind to an index, OR a WHERE form the planner fails to rewrite into
//   an index seek (classic: MATCH + WHERE on property when no usable index,
//   or planner chooses scan + filter for other cost reasons).
//
// NodeIndexSeek
//   Meaning: B-tree (range) / unique index lookup for a property value.
//   Triggers: equality (or range) predicate on a property that has a RANGE
//   INDEX or UNIQUE CONSTRAINT backing index, ideally expressed as
//   MATCH (e:Employee {employeeId: $id}) or WHERE that the planner rewrites.
//   Cost: roughly O(log n) for the seek + O(k) for k matching nodes.
//
// Expand(All)
//   Meaning: for each input row, follow all relationships of the given type
//   / direction and emit neighbor rows.
//   Cardinality explosion: if each of R rows expands to degree d, output is
//   ~R*d. Chains of Expand multiply (R * d1 * d2 * ...). Dense hubs
//   (popular Applications/Services) amplify this quickly.
//
// VarLengthExpand(All) vs VarLengthExpand(Pruning)
//   (All): explore every path that matches the var-length pattern; can revisit
//   nodes along different paths; memory/path enumeration grows with path count.
//   (Pruning): can prune branches that cannot improve the result (e.g. when
//   only distinct end nodes matter, or shortest-path style goals). Fewer
//   intermediate paths → less memory and often fewer DbHits.
//   Unbounded * forces deep exploration; bounded *1..N caps depth.
//
// CartesianProduct
//   When: two (or more) MATCH pipelines with NO shared variables / no join
//   predicate connecting them — e.g. MATCH (e:Employee) ... MATCH (db:Database)
//   before a later pattern finally relates them.
//   Effect: every row from left × every row from right. With 10 employees and
//   3 databases that is already 30 pairs before useful filtering; in prod it
//   is catastrophic.
//   Eliminate: start from one indexed anchor; thread variables with WITH;
//   use a single connected pattern; or CALL { WITH e MATCH ... } so the
//   inner MATCH is correlated.
//
// Filter
//   Where: often immediately above a scan/expand when a WHERE predicate was
//   not pushed into an index seek.
//   Push earlier: rewrite predicates into MATCH maps / indexable forms so
//   Filter disappears or runs on far fewer rows. A Filter on 10M scanned
//   nodes is expensive even if only 1 row survives.
//
// EagerAggregation vs OrderedAggregation
//   EagerAggregation: build a hash table over all input before emitting
//   groups — higher memory, required when input is unordered.
//   OrderedAggregation: exploit pre-sorted input (ORDER BY / index order)
//   to aggregate streaming with less memory.
//   Prefer plans where sort+aggregate can use OrderedAggregation when
//   grouping keys align with sort order; avoid unnecessary Eager buffers.
//
// -----------------------------------------------------------------------------

// #############################################################################
// ===== SECTION 3: PROFILE ANALYSIS (WITH KNOWN OUTPUT) =====
// #############################################################################
// PROFILE executes the query and annotates each operator with actual Rows,
// DbHits, Memory, and Time. Run against the sample dataset after load.
// Numbers below are illustrative of the SAMPLE graph shape (not exact wall
// clock); re-run PROFILE locally and compare.
// #############################################################################

PROFILE
MATCH (e:Employee)
WHERE e.employeeId = 'EMP-001'
MATCH (db:Database)
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*]->(s:Service)-[:READS_FROM]->(db)
RETURN e.name, a.name, s.name, db.name;

// Illustrative PROFILE-style table for the SAMPLE dataset (~10 Employees,
// EMP-001 has 2 USES apps, each app fans out DEPENDS_ON → Service → Database):
//
// Operator                    | Rows | DbHits | Memory | Time (ms)
// ----------------------------|------|--------|--------|----------
// NodeByLabelScan(:Employee)  |  10  |  10    |   256B |   0.5
// Filter (employeeId)         |   1  |  10    |     0B |   0.1
// NodeByLabelScan(:Database)  |   3  |   3    |   128B |   0.2
// CartesianProduct            |   3  |   0    |   1.0KiB|  0.1
// Expand(All) USES            |   6  |   6    |   512B |   0.2
// VarLengthExpand DEPENDS_ON* |  12+ |  20+   |   2.0KiB|  0.8
// Expand(All) READS_FROM      |   6  |   8    |   512B |   0.3
// Filter / Apply join to db   |   4  |   4    |   256B |   0.2
// ProduceResults              |   4  |   0    |     0B |   0.1
//
// How to read this:
//   - 10 Employee DbHits to keep 1 row = wasted work (index seek would be ~1–2)
//   - CartesianProduct multiplies Employee×Database before the path is proven
//   - Unbounded DEPENDS_ON* inflates VarLengthExpand rows/DbHits even on a
//     tiny graph; on dense production graphs this is the first timeout cause
//
// Compare: actual Rows vs EXPLAIN estimated rows. If Expand estimates 2 but
// PROFILE shows hundreds, update statistics (ANALYZE) and tighten patterns.

// #############################################################################
// ===== SECTION 4: OPTIMIZATION 1 — INDEX ANCHORING =====
// #############################################################################
// Replace MATCH + WHERE with a map predicate on the unique property so the
// planner chooses NodeIndexSeek on Employee(employeeId).
// Complexity: O(n) label scan → O(log n) index lookup.
// #############################################################################

// Optimized: index-anchored lookup
MATCH (e:Employee {employeeId: 'EMP-001'})
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       db.name AS database_name;

EXPLAIN
MATCH (e:Employee {employeeId: 'EMP-001'})
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name, a.name, s.name, db.name;

// BEFORE (Section 1 style) vs AFTER (this section) — EXPLAIN comparison:
//
// BEFORE                                      | AFTER
// --------------------------------------------|--------------------------------
// NodeByLabelScan(:Employee)  ~10 est. rows   | NodeIndexSeek(:Employee
// Filter employeeId = 'EMP-001'               |   {employeeId})  ~1 est. row
// (then Cartesian / expands...)               | Expand USES → ...
//
// Anchoring on an indexed unique property = O(log n) seek instead of O(n)
// full label scan. On 1M employees that is the difference between milliseconds
// and a multi-second (or multi-minute) startup cost before any expansion.

// #############################################################################
// ===== SECTION 5: OPTIMIZATION 2 — BOUND VARIABLE-LENGTH TRAVERSAL =====
// #############################################################################
// Unbounded * explores every reachable path of any length → exponential
// worst-case fan-out in dense / cyclic dependency graphs.
// Bound depth to known architecture depth (here services are shallow).
//
// PRODUCTION RULE: always use depth limits on variable-length traversals
//   Prefer [:TYPE*1..N] or shortestPath with a bound. Never ship [:TYPE*]
//   to production unless the graph is proven tiny and acyclic AND monitored.
// #############################################################################

// Unbounded (anti-pattern fragment — do not use in prod)
// MATCH (a:Application)-[:DEPENDS_ON*]->(s:Service)

// Bounded *1..4 (preferred)
MATCH (e:Employee {employeeId: 'EMP-001'})
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       db.name AS database_name,
       // hop depth of the DEPENDS_ON portion is bounded by 4
       a.applicationId AS applicationId;

EXPLAIN
MATCH (e:Employee {employeeId: 'EMP-001'})
MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name, a.name, s.name, db.name;

// Worst-case complexity sketch:
//   Unbounded *: O(b^d) path explorations as branching factor b and depth d grow
//                without a cap on d (and cycles make "depth" effectively unbounded)
//   Bounded *1..N: O(b^N) still exponential in N, but N is a constant you choose
//                (architecture max hop count). That turns an open-ended risk into
//                a budgeted cost the SRE team can reason about.
// Depth limits prevent exponential fan-out from walking the entire connected
// component of the dependency graph on every request.

// #############################################################################
// ===== SECTION 6: OPTIMIZATION 3 — CALL {} IN TRANSACTIONS / SUBQUERY =====
// #############################################################################
// Independent MATCH clauses encourage CartesianProduct. Correlated CALL { }
// subqueries force the planner to pass driving variables inward so the inner
// MATCH is executed per outer row — not as an independent full scan joined
// by product.
//
// Note: CALL { } IN TRANSACTIONS is for batching writes in Neo4j 5.x.
// For this read-path teaching example we use correlated CALL { WITH e ... }
// which is the pattern that eliminates Cartesian risk. The IN TRANSACTIONS
// form is shown as a commented template for large write migrations.
// #############################################################################

// Correlated subquery: planner must respect variable passing of `e`
MATCH (e:Employee {employeeId: 'EMP-001'})
CALL {
  WITH e
  MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
  RETURN a, s, db
}
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       db.name AS database_name;

EXPLAIN
MATCH (e:Employee {employeeId: 'EMP-001'})
CALL {
  WITH e
  MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
  RETURN a, s, db
}
RETURN e.name, a.name, s.name, db.name;

// Why this beats MATCH (e) MATCH (db) MATCH (e)-[...]->(db):
//   - WITH e imports the already-sought employee into the subquery
//   - Inner MATCH starts from that node; no free-standing Database scan
//   - No CartesianProduct of Employees × Databases
//
// CALL { } IN TRANSACTIONS template (writes / batch migrations):
//   MATCH (n:Incident)
//   CALL {
//     WITH n
//     // mutate n in small batches
//     SET n.reviewed = true
//   } IN TRANSACTIONS OF 500 ROWS
//   RETURN count(*);

// #############################################################################
// ===== SECTION 7: OPTIMIZATION 4 — APOC FOR DEEP TRAVERSAL =====
// #############################################################################
// When Cypher var-length expands become hard to control, APOC path expanders
// give explicit bfs/dfs, filters, and maxLevel. Requires APOC plugin
// (docker-compose: NEO4J_PLUGINS=["apoc","graph-data-science"]).
//
// When to use which:
//   apoc.path.subgraphNodes  → IMPACT SETS: "which nodes are reachable?"
//                              (distinct nodes, not every path)
//   apoc.path.spanningTree   → TREES WITHOUT CYCLES: one parent path per node;
//                              good for dependency trees / blast-radius trees
// #############################################################################

// Impact set: all nodes reachable downstream from Alice's first application hop
MATCH (e:Employee {employeeId: 'EMP-001'})-[:USES]->(a:Application)
CALL apoc.path.subgraphNodes(a, {
  relationshipFilter: 'DEPENDS_ON>|READS_FROM>|HOSTED_ON>',
  maxLevel: 4
})
YIELD node
RETURN a.name AS application,
       labels(node) AS labels,
       coalesce(node.name, node.serviceId, node.databaseId, node.serverId) AS node_name;

// Spanning tree: acyclic tree of dependencies from FinanceSuite
MATCH (a:Application {applicationId: 'APP-001'})
CALL apoc.path.spanningTree(a, {
  relationshipFilter: 'DEPENDS_ON>|READS_FROM>|HOSTED_ON>',
  maxLevel: 4
})
YIELD path
RETURN path,
       length(path) AS hop_count
ORDER BY hop_count;

// Guidance:
//   - subgraphNodes: page "everything impacted by APP-001" without enumerating
//     duplicate paths to the same Database/Server
//   - spanningTree: build a single tree for UI / RCA diagrams; cycles in the
//     dependency graph will not explode into infinite walks

// #############################################################################
// ===== SECTION 8: FINAL OPTIMIZED QUERY =====
// #############################################################################
// Combines all four techniques:
//   1) Index map anchor on employeeId
//   2) Bounded DEPENDS_ON*1..4
//   3) Correlated CALL { WITH e ... } subquery (no Cartesian)
//   4) Optional APOC path for deep impact (commented alternative below)
// #############################################################################

MATCH (e:Employee {employeeId: 'EMP-001'})
CALL {
  WITH e
  MATCH (e)-[:USES]->(a:Application)-[dep:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
  RETURN a, s, db, dep
}
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       s.type AS service_type,
       db.name AS database_name,
       db.engine AS database_engine
ORDER BY application_name, service_name;

EXPLAIN
MATCH (e:Employee {employeeId: 'EMP-001'})
CALL {
  WITH e
  MATCH (e)-[:USES]->(a:Application)-[:DEPENDS_ON*1..4]->(s:Service)-[:READS_FROM]->(db:Database)
  RETURN a, s, db
}
RETURN e.name, a.name, s.name, db.name
ORDER BY a.name, s.name;

// Optional APOC alternative for the expansion leg (impact-oriented):
// MATCH (e:Employee {employeeId: 'EMP-001'})-[:USES]->(a:Application)
// CALL apoc.path.subgraphNodes(a, {
//   relationshipFilter: 'DEPENDS_ON>|READS_FROM>',
//   labelFilter: '>Service|>Database',
//   maxLevel: 4
// })
// YIELD node
// RETURN e.name, a.name, labels(node), coalesce(node.name, node.serviceId, node.databaseId);

// -----------------------------------------------------------------------------
// SIDE-BY-SIDE EXPLAIN COMPARISON (slow vs optimized)
// -----------------------------------------------------------------------------
//
// SLOW (Section 1)                         | OPTIMIZED (Section 8)
// -----------------------------------------|------------------------------------
// NodeByLabelScan(:Employee)  rows≈10      | NodeIndexSeek(:Employee)  rows≈1
// Filter employeeId           DbHits≈10    | (predicate folded into seek)
// NodeByLabelScan(:Database)  rows≈3       | (no free Database scan)
// CartesianProduct            rows≈3–30    | Apply / nested plan via CALL
// VarLengthExpand(All) *      unbounded    | VarLengthExpand *1..4  capped
// Expand READS_FROM + Filter               | Expand READS_FROM (connected)
// High DbHits / unstable time              | Low DbHits, stable latency
//
// Illustrative totals on sample data:
//   Slow:      Rows out ~4–6 useful, but DbHits often 50–100+ with product waste
//   Optimized: Rows out ~4, DbHits typically teens — seek + few expands only
//
// Assessor takeaway:
//   EXPLAIN to catch LabelScan / Cartesian / unbounded * before deploy.
//   PROFILE to validate actual Rows/DbHits against estimates.
//   Always: index-anchor + depth-bound + correlated subqueries; APOC when
//   you need controlled deep impact sets or spanning trees.
// -----------------------------------------------------------------------------
