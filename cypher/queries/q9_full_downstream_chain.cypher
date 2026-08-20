// =============================================================================
// q9_full_downstream_chain.cypher
// =============================================================================
// WHAT: Return the complete downstream dependency chain for an application:
//       Application → Service → Database → Server, with relationship properties
//       exposed via named variables r1, r2, r3.
//
// WHY NAME EVERY RELATIONSHIP (r1, r2, r3):
//   Named relationships make properties available in RETURN (e.g. r1.weight
//   as dependency_criticality). Unnamed relationships cannot be referenced
//   for properties or for building richer path analytics.
//
// INDEXES USED:
//   - Application.applicationId uniqueness → NodeIndexSeek at start
//   - Database / Server uniqueness and Server.region range index (returned)
//
// EXPECTED RESULT SHAPE (main query):
//   | application | app_version | service | svc_type | svc_sla_ms |
//   | database | db_engine | db_size_gb | server | server_region | server_os |
//   | dependency_criticality |
//   Ordered by r1.weight DESC (most critical first).
//   Sample (APP-001): auth-service (weight 1.0) and reporting-svc (0.8) both
//   to fin-postgres-prod on db-primary-east.
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param applicationId => 'APP-001'

MATCH (a:Application {applicationId: $applicationId})-[r1:DEPENDS_ON]->(s:Service)-[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
RETURN a.name AS application,
       a.version AS app_version,
       s.name AS service,
       s.type AS svc_type,
       s.sla_ms AS svc_sla_ms,
       db.name AS database,
       db.engine AS db_engine,
       db.size_gb AS db_size_gb,
       srv.name AS server,
       srv.region AS server_region,
       srv.os AS server_os,
       r1.weight AS dependency_criticality
ORDER BY r1.weight DESC;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (a:Application {applicationId: 'APP-001'})-[r1:DEPENDS_ON]->(s:Service)-[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
RETURN a.name AS application,
       a.version AS app_version,
       s.name AS service,
       s.type AS svc_type,
       s.sla_ms AS svc_sla_ms,
       db.name AS database,
       db.engine AS db_engine,
       db.size_gb AS db_size_gb,
       srv.name AS server,
       srv.region AS server_region,
       srv.os AS server_os,
       r1.weight AS dependency_criticality
ORDER BY r1.weight DESC;

// --- EXTENSION: return the full path as a graph object ----------------------
// Useful for visualization clients that consume path / subgraph results.

MATCH path = (a:Application {applicationId: $applicationId})-[r1:DEPENDS_ON]->(s:Service)-[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
RETURN path,
       r1.weight AS dependency_criticality
ORDER BY r1.weight DESC;

// --- EXTENSION TEST ---------------------------------------------------------

MATCH path = (a:Application {applicationId: 'APP-001'})-[r1:DEPENDS_ON]->(s:Service)-[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
RETURN path,
       r1.weight AS dependency_criticality
ORDER BY r1.weight DESC;

// --- BONUS AGGREGATION: unique servers this application depends on ----------

MATCH (a:Application {applicationId: $applicationId})-[:DEPENDS_ON]->(:Service)-[:READS_FROM]->(:Database)-[:HOSTED_ON]->(srv:Server)
RETURN a.name AS application,
       count(DISTINCT srv) AS unique_servers;

// --- BONUS TEST -------------------------------------------------------------

MATCH (a:Application {applicationId: 'APP-001'})-[:DEPENDS_ON]->(:Service)-[:READS_FROM]->(:Database)-[:HOSTED_ON]->(srv:Server)
RETURN a.name AS application,
       count(DISTINCT srv) AS unique_servers;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (a:Application {applicationId: $applicationId})-[r1:DEPENDS_ON]->(s:Service)-[r2:READS_FROM]->(db:Database)-[r3:HOSTED_ON]->(srv:Server)
// RETURN a.name, a.version, s.name, s.type, s.sla_ms, db.name, db.engine, db.size_gb,
//        srv.name, srv.region, srv.os, r1.weight
// ORDER BY r1.weight DESC;
//
// Expected plan shape:
//   - NodeIndexSeek(:Application {applicationId})
//   - Expand(Outgoing) DEPENDS_ON → Service
//   - Expand(Outgoing) READS_FROM → Database
//   - Expand(Outgoing) HOSTED_ON → Server
//   - Projection + Sort by weight DESC
