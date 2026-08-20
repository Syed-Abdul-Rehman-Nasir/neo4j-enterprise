// =============================================================================
// q1_finance_apps.cypher
// =============================================================================
// WHAT: Find all applications used by employees in a given department
//       (default use case: Finance). Returns each application with its tier,
//       the list of department users, and how many of those users use it.
//
// WHY WRITTEN THIS WAY:
//   Two (actually three) chained MATCH clauses instead of one long pattern.
//   Starting at Department lets the planner lock onto a small, selective set of
//   nodes first, then expand to employees and applications. A single long
//   pattern can encourage less optimal join order.
//
// WHY MATCH DEPARTMENT FIRST:
//   Department is the most selective anchor. Prefer matching by deptId for a
//   unique-constraint NodeIndexSeek. Matching by name (this query's parameter)
//   still starts from the Department label and filters early. Anchoring later
//   (e.g. scanning all Applications first) expands a larger working set.
//
// INDEXES USED:
//   - Department.deptId uniqueness constraint (backing index) — ideal when
//     filtering by deptId; name filter uses label scan + property filter
//   - Application.applicationId uniqueness (returned identifiers)
//   - Application.tier / Application.owner range indexes (available for filters)
//
// EXPECTED RESULT SHAPE (one row per application):
//   | application_name | applicationId | tier | finance_users (list) | user_count |
//   Ordered by user_count DESC.
//   Sample (Finance): FinanceSuite with 4 users; DataLakeDash with 1 (Alice).
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param departmentName => 'Finance'

MATCH (d:Department {name: $departmentName})
MATCH (e:Employee)-[:BELONGS_TO]->(d)
MATCH (e)-[:USES]->(a:Application)
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       collect(e.name) AS finance_users,
       count(e) AS user_count
ORDER BY user_count DESC;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (d:Department {name: 'Finance'})
MATCH (e:Employee)-[:BELONGS_TO]->(d)
MATCH (e)-[:USES]->(a:Application)
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       collect(e.name) AS finance_users,
       count(e) AS user_count
ORDER BY user_count DESC;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (d:Department {name: $departmentName})
// MATCH (e:Employee)-[:BELONGS_TO]->(d)
// MATCH (e)-[:USES]->(a:Application)
// RETURN a.name, a.applicationId, a.tier, collect(e.name), count(e)
// ORDER BY count(e) DESC;
//
// Expected plan shape:
//   - NodeByLabelScan / Filter on Department.name (or NodeIndexSeek if using deptId)
//   - Expand(Incoming) BELONGS_TO → Employee
//   - Expand(Outgoing) USES → Application
//   - EagerAggregation (collect / count)
//   - Sort by user_count
