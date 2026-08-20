// =============================================================================
// Schema: uniqueness constraints, existence constraints, and range indexes
// Run this script BEFORE loading any data. Safe to re-run (idempotent).
// =============================================================================
//
// Why uniqueness constraints also create backing indexes:
//   A uniqueness constraint must look up existing values on write. Neo4j
//   automatically creates a backing index for that property so uniqueness
//   checks (and equality lookups) are efficient without a separate CREATE INDEX.
//
// Constraint vs plain index:
//   - Constraint: enforces a data-integrity rule (unique / not null). Violating
//     writes are rejected.
//   - Plain index: accelerates reads/filters only; it does not enforce integrity.
//
// How to confirm an index is being used:
//   Run EXPLAIN (or PROFILE) on a query that filters by the indexed property.
//   Look for NodeIndexSeek (or similar index operators) in the plan.
//   NodeByLabelScan means the planner is scanning the label instead of seeking
//   the index — often a missing or unused index.
//
// Why IF NOT EXISTS is critical for idempotency:
//   Without IF NOT EXISTS, re-running this script fails when objects already
//   exist. With IF NOT EXISTS, CREATE is a no-op if the named constraint/index
//   is already present, so the script is safe to run multiple times.
// =============================================================================

// -----------------------------------------------------------------------------
// UNIQUENESS CONSTRAINTS (entity IDs)
// -----------------------------------------------------------------------------

CREATE CONSTRAINT employee_employeeId IF NOT EXISTS
FOR (e:Employee) REQUIRE e.employeeId IS UNIQUE;

CREATE CONSTRAINT department_deptId IF NOT EXISTS
FOR (d:Department) REQUIRE d.deptId IS UNIQUE;

CREATE CONSTRAINT application_applicationId IF NOT EXISTS
FOR (a:Application) REQUIRE a.applicationId IS UNIQUE;

CREATE CONSTRAINT service_serviceId IF NOT EXISTS
FOR (s:Service) REQUIRE s.serviceId IS UNIQUE;

CREATE CONSTRAINT database_databaseId IF NOT EXISTS
FOR (db:Database) REQUIRE db.databaseId IS UNIQUE;

CREATE CONSTRAINT server_serverId IF NOT EXISTS
FOR (srv:Server) REQUIRE srv.serverId IS UNIQUE;

CREATE CONSTRAINT incident_incidentId IF NOT EXISTS
FOR (i:Incident) REQUIRE i.incidentId IS UNIQUE;

// -----------------------------------------------------------------------------
// PROPERTY EXISTENCE CONSTRAINTS (Enterprise: IS NOT NULL)
// -----------------------------------------------------------------------------

CREATE CONSTRAINT employee_email_not_null IF NOT EXISTS
FOR (e:Employee) REQUIRE e.email IS NOT NULL;

CREATE CONSTRAINT employee_name_not_null IF NOT EXISTS
FOR (e:Employee) REQUIRE e.name IS NOT NULL;

CREATE CONSTRAINT incident_severity_not_null IF NOT EXISTS
FOR (i:Incident) REQUIRE i.severity IS NOT NULL;

CREATE CONSTRAINT incident_status_not_null IF NOT EXISTS
FOR (i:Incident) REQUIRE i.status IS NOT NULL;

CREATE CONSTRAINT application_name_not_null IF NOT EXISTS
FOR (a:Application) REQUIRE a.name IS NOT NULL;

// -----------------------------------------------------------------------------
// RANGE INDEXES (commonly filtered non-unique properties)
// -----------------------------------------------------------------------------

CREATE RANGE INDEX incident_severity IF NOT EXISTS
FOR (i:Incident) ON (i.severity);

CREATE RANGE INDEX incident_status IF NOT EXISTS
FOR (i:Incident) ON (i.status);

CREATE RANGE INDEX incident_ts IF NOT EXISTS
FOR (i:Incident) ON (i.ts);

CREATE RANGE INDEX application_tier IF NOT EXISTS
FOR (a:Application) ON (a.tier);

CREATE RANGE INDEX application_owner IF NOT EXISTS
FOR (a:Application) ON (a.owner);

CREATE RANGE INDEX employee_role IF NOT EXISTS
FOR (e:Employee) ON (e.role);

CREATE RANGE INDEX employee_email IF NOT EXISTS
FOR (e:Employee) ON (e.email);

CREATE RANGE INDEX database_env IF NOT EXISTS
FOR (db:Database) ON (db.env);

CREATE RANGE INDEX database_engine IF NOT EXISTS
FOR (db:Database) ON (db.engine);

CREATE RANGE INDEX server_region IF NOT EXISTS
FOR (srv:Server) ON (srv.region);

CREATE RANGE INDEX service_type IF NOT EXISTS
FOR (s:Service) ON (s.type);

// -----------------------------------------------------------------------------
// COMPOSITE INDEX (troubleshooting filters on severity + status)
// -----------------------------------------------------------------------------

CREATE RANGE INDEX incident_severity_status IF NOT EXISTS
FOR (i:Incident) ON (i.severity, i.status);

// Q1 anchors on Department.name — without this index, Q1 performs a
// NodeByLabelScan on Department before traversing to Employee and Application.
CREATE RANGE INDEX idx_dept_name IF NOT EXISTS
FOR (d:Department) ON (d.name);

// -----------------------------------------------------------------------------
// VERIFICATION (run manually; expected outcomes noted below)
// -----------------------------------------------------------------------------
// SHOW CONSTRAINTS YIELD name, type, labelsOrTypes, properties, state
//   -- Expect 12 constraints (7 uniqueness + 5 existence), all ONLINE
// SHOW INDEXES YIELD name, type, labelsOrTypes, properties, state
//   -- Expect range indexes including idx_dept_name, incident_severity_status, …
//   -- and uniqueness backing indexes; all state = ONLINE
// EXPLAIN MATCH (e:Employee {employeeId: 'EMP-001'}) RETURN e
// -- Expected: NodeIndexSeek, NOT NodeByLabelScan
// EXPLAIN MATCH (d:Department {name: 'Finance'}) RETURN d
// -- Expected: NodeIndexSeek via idx_dept_name
