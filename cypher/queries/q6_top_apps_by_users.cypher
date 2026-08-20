// =============================================================================
// q6_top_apps_by_users.cypher
// =============================================================================
// WHAT: Return the top N applications by unique employee count, with owner,
//       tier, and a distinct department breakdown of those users.
//
// WHY count(DISTINCT e) NOT count(e):
//   If an employee has multiple USES relationships to the same application
//   (duplicate edges, historical USES rows, or modeling mistakes), count(e)
//   would inflate unique_users. count(DISTINCT e) counts each employee once
//   per application regardless of how many USES edges connect them.
//
// WHY WRITTEN THIS WAY:
//   Aggregate unique users and department names in WITH, then ORDER BY + LIMIT
//   so only the top $limit apps are returned.
//
// WHY applicationId ASC TIE-BREAK:
//   Multiple apps can share the same unique_users count (sample: DeployPortal,
//   HRConnect, DataLakeDash all have 2). Without a secondary ORDER BY key,
//   Neo4j may return ties in non-deterministic order — breaking test assertions
//   and making LIMIT-based paging unstable in production APIs.
//
// INDEXES USED:
//   - Application.applicationId uniqueness
//   - Application.tier / Application.owner range indexes (returned / filterable)
//
// EXPECTED RESULT SHAPE:
//   | application_name | applicationId | owner | tier | unique_users | departments |
//   Sample ($limit = 3): FinanceSuite (4), then DeployPortal / DataLakeDash /
//   HRConnect (2 each) — ties broken by applicationId ASC for stable order.
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param limit => 3

MATCH (a:Application)<-[:USES]-(e:Employee)
OPTIONAL MATCH (e)-[:BELONGS_TO]->(d:Department)
WITH a,
     count(DISTINCT e) AS unique_users,
     collect(DISTINCT d.name) AS departments
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier,
       unique_users,
       departments
ORDER BY unique_users DESC, applicationId ASC
LIMIT $limit;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (a:Application)<-[:USES]-(e:Employee)
OPTIONAL MATCH (e)-[:BELONGS_TO]->(d:Department)
WITH a,
     count(DISTINCT e) AS unique_users,
     collect(DISTINCT d.name) AS departments
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier,
       unique_users,
       departments
ORDER BY unique_users DESC, applicationId ASC
LIMIT 3;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (a:Application)<-[:USES]-(e:Employee)
// OPTIONAL MATCH (e)-[:BELONGS_TO]->(d:Department)
// WITH a, count(DISTINCT e) AS unique_users, collect(DISTINCT d.name) AS departments
// RETURN a.name, a.applicationId, a.owner, a.tier, unique_users, departments
// ORDER BY unique_users DESC, applicationId ASC
// LIMIT $limit;
//
// Expected plan shape:
//   - NodeByLabelScan(:Application) or similar
//   - Expand(Incoming) USES → Employee
//   - OptionalExpand BELONGS_TO → Department
//   - EagerAggregation (Distinct count / collect)
//   - Sort (unique_users DESC, applicationId ASC) + Limit
