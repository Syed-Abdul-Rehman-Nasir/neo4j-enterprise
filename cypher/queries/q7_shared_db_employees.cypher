// =============================================================================
// q7_shared_db_employees.cypher
// =============================================================================
// WHAT: Find employees who use 2 or more applications that all depend
//       (directly or via short DEPENDS_ON chains) on the same database.
//
// BLAST-RADIUS NOTE:
//   This query reveals employees with high blast-radius exposure to a single
//   DB failure — if that database goes down, multiple of their apps fail at
//   once, concentrating operational and business impact on those people.
//
// WHY WRITTEN THIS WAY:
//   Collect DISTINCT applications per (employee, database) in WITH, then
//   filter with size(apps) >= $minApps. Post-aggregation filtering is the
//   correct pattern (same idea as q3).
//
// INDEXES USED:
//   - Employee.employeeId uniqueness (identity)
//   - Database.databaseId uniqueness
//   - Application.applicationId uniqueness
//
// EXPECTED RESULT SHAPE:
//   | employee_name | shared_database | applications (list) | app_count |
//   Ordered by app_count DESC.
//   Sample ($minApps = 2): may be empty — current dataset has no employee
//   using two different apps that both reach the same database (e.g. Alice
//   uses FinanceSuite→DB-001 and DataLakeDash→DB-003).
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param minApps => 2

MATCH (e:Employee)-[:USES]->(a:Application)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db:Database)
WITH e, db, collect(DISTINCT a) AS apps
WHERE size(apps) >= $minApps
RETURN e.name AS employee_name,
       db.name AS shared_database,
       [x IN apps | x.name] AS applications,
       size(apps) AS app_count
ORDER BY app_count DESC;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (e:Employee)-[:USES]->(a:Application)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db:Database)
WITH e, db, collect(DISTINCT a) AS apps
WHERE size(apps) >= 2
RETURN e.name AS employee_name,
       db.name AS shared_database,
       [x IN apps | x.name] AS applications,
       size(apps) AS app_count
ORDER BY app_count DESC;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (e:Employee)-[:USES]->(a:Application)-[:DEPENDS_ON*1..3]->(s:Service)-[:READS_FROM]->(db:Database)
// WITH e, db, collect(DISTINCT a) AS apps
// WHERE size(apps) >= $minApps
// RETURN e.name, db.name, [x IN apps | x.name], size(apps)
// ORDER BY size(apps) DESC;
//
// Expected plan shape:
//   - NodeByLabelScan(:Employee) or index-backed expands
//   - Expand USES → Application
//   - VarLengthExpand DEPENDS_ON*1..3 → Service
//   - Expand READS_FROM → Database
//   - EagerAggregation (collect DISTINCT)
//   - Filter (size >= $minApps)
//   - Sort
