// =============================================================================
// q4_db_impact_analysis.cypher
// =============================================================================
// WHAT: Find all employees impacted when a specific database has an issue by
//       walking inbound from Database ← Service ← Application ← Employee and
//       attaching the employee's department.
//
// BLAST-RADIUS CONCEPT:
//   A database outage does not only affect the DB team — every service that
//   reads from it, every application that depends on those services, and every
//   employee who uses those applications is in the blast radius. This query
//   materializes that fan-out for incident response and communication lists.
//
// WHY DISTINCT IS CRITICAL:
//   One employee may USE multiple applications that both depend on services
//   reading the same database (e.g. Alice uses FinanceSuite and DataLakeDash).
//   Without DISTINCT (or careful projection), the same person appears once per
//   (app, service) path, inflating headcount and confusing responders.
//   Here we keep via_application / via_service for triage context while using
//   DISTINCT on the full return row so identical path rows are not duplicated.
//
// WHY WRITTEN THIS WAY:
//   Anchor on Database by databaseId (unique index), then expand inbound.
//   Second MATCH attaches BELONGS_TO for department without lengthening the
//   primary impact path pattern.
//
// INDEXES USED:
//   - Database.databaseId uniqueness → NodeIndexSeek at start
//   - Employee.email range index (returned; available for follow-up lookup)
//   - Application / Service uniqueness constraints for identity
//
// EXPECTED RESULT SHAPE:
//   | impacted_employee | email | department | via_application | via_service | database_name |
//   Ordered by employee name.
//   Sample (DB-001): Finance employees via FinanceSuite / auth-service or
//   reporting-svc → fin-postgres-prod.
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param databaseId => 'DB-001'

MATCH (db:Database {databaseId: $databaseId})<-[:READS_FROM]-(s:Service)<-[:DEPENDS_ON]-(a:Application)<-[:USES]-(e:Employee)
MATCH (e)-[:BELONGS_TO]->(d:Department)
RETURN DISTINCT e.name AS impacted_employee,
                e.email AS email,
                d.name AS department,
                a.name AS via_application,
                s.name AS via_service,
                db.name AS database_name
ORDER BY impacted_employee;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (db:Database {databaseId: 'DB-001'})<-[:READS_FROM]-(s:Service)<-[:DEPENDS_ON]-(a:Application)<-[:USES]-(e:Employee)
MATCH (e)-[:BELONGS_TO]->(d:Department)
RETURN DISTINCT e.name AS impacted_employee,
                e.email AS email,
                d.name AS department,
                a.name AS via_application,
                s.name AS via_service,
                db.name AS database_name
ORDER BY impacted_employee;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (db:Database {databaseId: $databaseId})<-[:READS_FROM]-(s:Service)<-[:DEPENDS_ON]-(a:Application)<-[:USES]-(e:Employee)
// MATCH (e)-[:BELONGS_TO]->(d:Department)
// RETURN DISTINCT e.name, e.email, d.name, a.name, s.name, db.name
// ORDER BY e.name;
//
// Expected plan shape:
//   - NodeIndexSeek(:Database {databaseId})
//   - Expand(Incoming) READS_FROM → Service
//   - Expand(Incoming) DEPENDS_ON → Application
//   - Expand(Incoming) USES → Employee
//   - Expand(Outgoing) BELONGS_TO → Department
//   - Distinct + Sort
