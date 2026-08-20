// =============================================================================
// q2_employee_chain.cypher
// =============================================================================
// WHAT: For a given employee, traverse the full dependency chain
//       Employee → Application → Service → Database and return each hop with
//       the DEPENDS_ON weight.
//
// WHY WRITTEN THIS WAY:
//   The first MATCH anchors on Employee by employeeId so the planner starts
//   with a unique-index seek (one node). The second MATCH expands the known
//   chain outward. Separating the anchor from the expansion keeps the plan
//   readable and predictable.
//
// INDEXES USED:
//   - Employee.employeeId uniqueness constraint → NodeIndexSeek at plan start
//   - Application.applicationId, Service.serviceId, Database.databaseId
//     uniqueness (identity / integrity along the chain)
//
// EXPECTED RESULT SHAPE (one row per app→service→db path):
//   | employee_name | application_name | service_name | service_type |
//   | database_name | database_engine | dependency_weight |
//   Ordered by application_name, service_name.
//   Sample (EMP-001 Alice): FinanceSuite → auth-service/reporting-svc →
//   fin-postgres-prod; DataLakeDash → data-ingest/search-api → datalake-pg-prod.
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param employeeId => 'EMP-001'

MATCH (e:Employee {employeeId: $employeeId})
MATCH (e)-[:USES]->(a:Application)-[dep:DEPENDS_ON]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       s.type AS service_type,
       db.name AS database_name,
       db.engine AS database_engine,
       dep.weight AS dependency_weight
ORDER BY application_name, service_name;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (e:Employee {employeeId: 'EMP-001'})
MATCH (e)-[:USES]->(a:Application)-[dep:DEPENDS_ON]->(s:Service)-[:READS_FROM]->(db:Database)
RETURN e.name AS employee_name,
       a.name AS application_name,
       s.name AS service_name,
       s.type AS service_type,
       db.name AS database_name,
       db.engine AS database_engine,
       dep.weight AS dependency_weight
ORDER BY application_name, service_name;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (e:Employee {employeeId: $employeeId})
// MATCH (e)-[:USES]->(a:Application)-[dep:DEPENDS_ON]->(s:Service)-[:READS_FROM]->(db:Database)
// RETURN e.name, a.name, s.name, s.type, db.name, db.engine, dep.weight
// ORDER BY a.name, s.name;
//
// Expected plan shape:
//   - NodeIndexSeek(:Employee {employeeId})   ← must appear at the start
//   - Expand(Outgoing) USES → Application
//   - Expand(Outgoing) DEPENDS_ON → Service
//   - Expand(Outgoing) READS_FROM → Database
//   - Projection + Sort
// NOT expected at start: NodeByLabelScan(:Employee)
