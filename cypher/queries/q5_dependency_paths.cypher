// =============================================================================
// q5_dependency_paths.cypher
// =============================================================================
// WHAT: Return all dependency paths between a specific Application and a
//       specific Database using variable-length DEPENDS_ON (1..3 hops) then
//       a READS_FROM hop into the target database.
//
// WHY WRITTEN THIS WAY:
//   Applications depend on services (DEPENDS_ON); services read databases
//   (READS_FROM). Bounding DEPENDS_ON to *1..3 covers direct and shallow
//   multi-hop service chains without opening the graph unbounded. Paths are
//   returned with a readable name list and hop count; shortest first.
//
// WHY UNBOUNDED TRAVERSAL (*) IS DANGEROUS IN PRODUCTION:
//   Pattern (a)-[*]->(b) or even (a)-[:DEPENDS_ON*]->(s) with no upper bound
//   can explore enormous path spaces (cycles, dense subgraphs), cause memory
//   pressure, hit transaction timeouts, and lock planners into VarLengthExpand
//   with no guaranteed finish time. Always set an upper bound (*1..N) that
//   matches known architecture depth, or use shortestPath when only one path
//   is required.
//
// INDEXES USED:
//   - Application.applicationId uniqueness → NodeIndexSeek
//   - Database.databaseId uniqueness → NodeIndexSeek
//
// EXPECTED RESULT SHAPE (main query):
//   | path | node_names (list) | hop_count |
//   Ordered by hop_count ASC (shortest first).
//   Sample (APP-001 → DB-001): FinanceSuite → auth-service → fin-postgres-prod
//   and FinanceSuite → reporting-svc → fin-postgres-prod (hop_count 2 each).
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param applicationId => 'APP-001'
// :param databaseId => 'DB-001'

MATCH (a:Application {applicationId: $applicationId})
MATCH (db:Database {databaseId: $databaseId})
MATCH path = (a)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db)
RETURN path,
       [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)] AS node_names,
       length(path) AS hop_count
ORDER BY hop_count ASC;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (a:Application {applicationId: 'APP-001'})
MATCH (db:Database {databaseId: 'DB-001'})
MATCH path = (a)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db)
RETURN path,
       [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)] AS node_names,
       length(path) AS hop_count
ORDER BY hop_count ASC;

// --- VARIANT: shortestPath only — PRODUCTION --------------------------------
// Use when only the single shortest path is needed (cheaper than enumerating
// all bounded paths). Relationship types cover both hops in the chain.

MATCH (a:Application {applicationId: $applicationId})
MATCH (db:Database {databaseId: $databaseId})
MATCH path = shortestPath((a)-[:DEPENDS_ON|READS_FROM*1..4]->(db))
RETURN path,
       [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)] AS node_names,
       length(path) AS hop_count;

// --- VARIANT: shortestPath only — TEST --------------------------------------

MATCH (a:Application {applicationId: 'APP-001'})
MATCH (db:Database {databaseId: 'DB-001'})
MATCH path = shortestPath((a)-[:DEPENDS_ON|READS_FROM*1..4]->(db))
RETURN path,
       [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)] AS node_names,
       length(path) AS hop_count;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (a:Application {applicationId: $applicationId})
// MATCH (db:Database {databaseId: $databaseId})
// MATCH path = (a)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db)
// RETURN path, [n IN nodes(path) | coalesce(n.name, n.applicationId, n.serviceId, n.databaseId)], length(path)
// ORDER BY length(path);
//
// Expected plan shape:
//   - NodeIndexSeek(:Application {applicationId})
//   - NodeIndexSeek(:Database {databaseId})
//   - VarLengthExpand(Into/All) DEPENDS_ON*1..3 → Service
//   - Expand(Outgoing) READS_FROM → Database (filtered to bound db)
//   - Projection (list comprehension) + Sort by hop_count
//
// For shortestPath variant, expect ShortestPath / bidirectional BFS style
// operators instead of enumerating all var-length paths.
