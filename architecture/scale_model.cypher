// =============================================================================
// architecture/scale_model.cypher
// Executable companion to SCALE_DESIGN.md (Neo4j 5.15+ Enterprise + APOC).
// Target scale: ~5M Component nodes, ~100M dependency-class relationships.
// =============================================================================

// =============================================================================
// === SECTION 1: SCHEMA FOR SCALE ===
// Uniqueness for CDC/MERGE entry points, range/composite for filters,
// full-text for search UX, vector for semantic similarity (off blast-radius path).
// Safe to re-run (IF NOT EXISTS). Create AFTER offline bulk import.
// =============================================================================

// --- Uniqueness constraints (8) ---

CREATE CONSTRAINT application_applicationId IF NOT EXISTS
FOR (a:Application) REQUIRE a.applicationId IS UNIQUE;

CREATE CONSTRAINT service_serviceId IF NOT EXISTS
FOR (s:Service) REQUIRE s.serviceId IS UNIQUE;

CREATE CONSTRAINT database_databaseId IF NOT EXISTS
FOR (db:Database) REQUIRE db.databaseId IS UNIQUE;

CREATE CONSTRAINT server_serverId IF NOT EXISTS
FOR (srv:Server) REQUIRE srv.serverId IS UNIQUE;

CREATE CONSTRAINT networkdevice_deviceId IF NOT EXISTS
FOR (nd:NetworkDevice) REQUIRE nd.deviceId IS UNIQUE;

CREATE CONSTRAINT team_teamId IF NOT EXISTS
FOR (t:Team) REQUIRE t.teamId IS UNIQUE;

CREATE CONSTRAINT customer_customerId IF NOT EXISTS
FOR (c:Customer) REQUIRE c.customerId IS UNIQUE;

CREATE CONSTRAINT incident_incidentId IF NOT EXISTS
FOR (i:Incident) REQUIRE i.incidentId IS UNIQUE;

// --- Range indexes (blast-radius partitioning / dashboards) ---

CREATE RANGE INDEX service_tier IF NOT EXISTS
FOR (s:Service) ON (s.tier);

CREATE RANGE INDEX service_environment IF NOT EXISTS
FOR (s:Service) ON (s.environment);

CREATE RANGE INDEX incident_severity_status IF NOT EXISTS
FOR (i:Incident) ON (i.severity, i.status);

// --- Full-text (search-as-you-type; not blast-radius entry) ---

CREATE FULLTEXT INDEX component_name_fts IF NOT EXISTS
FOR (c:Component) ON EACH [c.name];

// --- Vector index (Neo4j 5.15+; semantic similarity only) ---

CREATE VECTOR INDEX component_desc_embedding IF NOT EXISTS
FOR (c:Component) ON (c.descriptionEmbedding)
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 768,
    `vector.similarity_function`: 'cosine'
  }
};


// =============================================================================
// === SECTION 2: BLAST RADIUS — PRODUCTION QUERY ===
// Params: $serviceId, $pageSkip, $pageLimit
// Entry: unique index seek on Service.serviceId
// Expand: APOC inbound DEPENDS_ON (bounded maxLevel) — never unbounded *
// Customers: CALL {} IN TRANSACTIONS — never hold ~50M SUBSCRIBED_TO in one tx
//
// Expected EXPLAIN operators (warm cache):
//   NodeUniqueIndexSeek | NodeIndexSeek  (Service.serviceId)
//   ProcedureCall        (apoc.path.subgraphNodes)
//   EagerAggregation / Distinct (apps, dbs, teams)
//   Apply + subquery with IN TRANSACTIONS (customer fan-out)
//   Skip / Limit         (pagination)
//
// Execution estimate at target scale: ~500 ms P90 (warm page cache, ~100 apps/page).
// =============================================================================

// :param serviceId  => 'SVC-AUTH-001'
// :param pageSkip   => 0
// :param pageLimit  => 100

MATCH (s:Service {serviceId: $serviceId})
CALL apoc.path.subgraphNodes(s, {
  relationshipFilter: '<DEPENDS_ON',
  labelFilter: '>Application|>Database|/Service',
  maxLevel: 6,
  bfs: true
})
YIELD node AS n
WITH s, collect(DISTINCT n) AS nodes
WITH s,
     [x IN nodes WHERE x:Application | x] AS apps,
     [x IN nodes WHERE x:Database    | x] AS dbs
WITH s, apps, dbs,
     [db IN dbs | {databaseId: db.databaseId, name: db.name}] AS impactedDatabases
UNWIND apps AS app
WITH s, app, impactedDatabases
ORDER BY app.applicationId
SKIP $pageSkip LIMIT $pageLimit

OPTIONAL MATCH (t:Team)-[:OWNS]->(app)
WITH s, app, impactedDatabases, collect(DISTINCT t.teamId) AS teamIds

CALL {
  WITH app
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
       app.tier AS applicationTier,
       teamIds,
       impactedDatabases,
       customerCount
ORDER BY applicationId;


// =============================================================================
// === SECTION 3: PRE-COMPUTED BLAST RADIUS UPDATE JOB ===
// Scheduled CronJob (every 6h) on an analytics read replica; writes go to primary.
// Driver: apoc.periodic.iterate over tier-1 services (service_tier range index).
// Batch: 100 services per transaction.
// ON ERROR CONTINUE: errorHandling: 'continue' — inspect failedParams / iterate stats.
// Hot-path read after job: property lookup ~1–5 ms vs live ~500 ms P90.
// =============================================================================

CALL apoc.periodic.iterate(
  '
  MATCH (s:Service)
  WHERE s.tier = 1
  RETURN s
  ',
  '
  WITH s
  CALL apoc.path.subgraphNodes(s, {
    relationshipFilter: "<DEPENDS_ON",
    labelFilter: ">Application|>Database|/Service",
    maxLevel: 6,
    bfs: true
  })
  YIELD node AS n
  WITH s, collect(DISTINCT n) AS nodes
  WITH s,
       [x IN nodes WHERE x:Application | x] AS apps,
       [x IN nodes WHERE x:Database    | x] AS dbs
  WITH s, apps, dbs,
       [a IN apps | a.applicationId] AS appIds,
       [d IN dbs  | d.databaseId]    AS dbIds
  UNWIND (CASE WHEN size(apps) = 0 THEN [null] ELSE apps END) AS app
  OPTIONAL MATCH (c:Customer)-[:SUBSCRIBED_TO]->(app)
  WITH s, appIds, dbIds, count(DISTINCT c) AS customerCount
  SET s.blast_radius_app_ids         = appIds,
      s.blast_radius_app_count       = size(appIds),
      s.blast_radius_db_ids          = dbIds,
      s.blast_radius_db_count        = size(dbIds),
      s.blast_radius_customer_count  = customerCount,
      s.blast_radius_computed_at     = datetime()
  ',
  {
    batchSize: 100,
    parallel: false,
    errorHandling: 'continue'
  }
)
YIELD batches, total, timeTaken, committedOperations, failedOperations, failedParams
RETURN batches, total, timeTaken, committedOperations, failedOperations, failedParams;
// failedOperations > 0 / non-empty failedParams => inspect logs; continue skipped bad batches.


// =============================================================================
// === SECTION 4: IMPACT REPORT QUERY ===
// Dashboard-oriented single RETURN for service failure $serviceId.
// Columns: apps (tier + owner), databases, teams/departments, customer estimate,
//          open P1 incidents on any impacted application.
// Uses composite Incident(severity, status) for open-P1 filter.
// =============================================================================

// :param serviceId => 'SVC-AUTH-001'

MATCH (s:Service {serviceId: $serviceId})
CALL apoc.path.subgraphNodes(s, {
  relationshipFilter: '<DEPENDS_ON',
  labelFilter: '>Application|>Database|/Service',
  maxLevel: 6,
  bfs: true
})
YIELD node AS n
WITH s, collect(DISTINCT n) AS nodes
WITH s,
     [x IN nodes WHERE x:Application | x] AS apps,
     [x IN nodes WHERE x:Database    | x] AS dbs

// Owners / teams for impacted applications
UNWIND (CASE WHEN size(apps) = 0 THEN [null] ELSE apps END) AS app
OPTIONAL MATCH (t:Team)-[:OWNS]->(app)
WITH s, apps, dbs,
     collect(DISTINCT CASE
       WHEN app IS NULL THEN null
       ELSE {
         applicationId: app.applicationId,
         name: app.name,
         tier: app.tier,
         owner: coalesce(app.owner, t.name),
         teamId: t.teamId,
         teamName: t.name
       }
     END) AS appRows,
     collect(DISTINCT CASE WHEN t IS NULL THEN null ELSE {
       teamId: t.teamId,
       name: t.name,
       department: coalesce(t.department, t.name)
     } END) AS teamRows

WITH s, apps, dbs,
     [r IN appRows  WHERE r IS NOT NULL | r] AS impactedApplications,
     [r IN teamRows WHERE r IS NOT NULL | r] AS impactedTeams,
     [db IN dbs | {databaseId: db.databaseId, name: db.name}] AS impactedDatabases

// Estimated customer fan-out (distinct across all impacted apps)
UNWIND (CASE WHEN size(apps) = 0 THEN [null] ELSE apps END) AS app
OPTIONAL MATCH (c:Customer)-[:SUBSCRIBED_TO]->(app)
WITH s, apps, impactedApplications, impactedDatabases, impactedTeams,
     count(DISTINCT c) AS estimatedCustomerCount

// Open P1s currently affecting any impacted application
UNWIND (CASE WHEN size(apps) = 0 THEN [null] ELSE apps END) AS app
OPTIONAL MATCH (i:Incident)-[:AFFECTS]->(app)
WHERE i.severity = 'P1'
  AND i.status IN ['Open', 'Investigating']
WITH s, impactedApplications, impactedDatabases, impactedTeams, estimatedCustomerCount,
     collect(DISTINCT CASE WHEN i IS NULL THEN null ELSE {
       incidentId: i.incidentId,
       title: i.title,
       severity: i.severity,
       status: i.status,
       applicationId: app.applicationId
     } END) AS p1Rows

RETURN s.serviceId AS failedServiceId,
       s.name AS failedServiceName,
       s.tier AS failedServiceTier,
       impactedApplications,
       impactedDatabases,
       impactedTeams,
       estimatedCustomerCount,
       [r IN p1Rows WHERE r IS NOT NULL | r] AS openP1Incidents;


// =============================================================================
// === SECTION 5: TOP N CRITICAL DEPENDENCIES ===
// Top 10 services by blast radius (single points of failure).
// Prefer precomputed blast_radius_app_count from Section 3 (fast path).
// Live APOC form below is analytics-only at ~2M services — do not run on primary.
// =============================================================================

// --- Preferred: precomputed properties (after Section 3 job) ---

MATCH (s:Service)
WHERE s.blast_radius_app_count IS NOT NULL
RETURN s.serviceId AS serviceId,
       s.name AS name,
       s.tier AS tier,
       s.blast_radius_app_count AS impactedApplicationCount,
       s.blast_radius_customer_count AS blast_radius_customer_count,
       s.blast_radius_computed_at AS computedAt
ORDER BY impactedApplicationCount DESC
LIMIT 10;

// --- Live alternative (analytics replica only; expensive at target scale) ---
// MATCH (s:Service)
// CALL apoc.path.subgraphNodes(s, {
//   relationshipFilter: '<DEPENDS_ON',
//   labelFilter: '>Application|/Service',
//   maxLevel: 6,
//   bfs: true
// })
// YIELD node AS n
// WITH s, count(DISTINCT CASE WHEN n:Application THEN n END) AS impactedApplicationCount
// WHERE impactedApplicationCount > 0
// RETURN s.serviceId AS serviceId,
//        s.name AS name,
//        s.tier AS tier,
//        impactedApplicationCount,
//        s.blast_radius_customer_count AS blast_radius_customer_count,
//        s.blast_radius_computed_at AS computedAt
// ORDER BY impactedApplicationCount DESC
// LIMIT 10;
