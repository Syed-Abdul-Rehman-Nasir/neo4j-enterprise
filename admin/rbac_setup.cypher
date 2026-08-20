// =============================================================================
// admin/rbac_setup.cypher
// Enterprise RBAC model for the IT dependency graph
// Prerequisites: Neo4j Enterprise 5.x; run as neo4j (or equivalent admin)
// Target database/graph name: neo4j
// =============================================================================

// #############################################################################
// ===== SECTION 1: BUILT-IN ROLES OVERVIEW =====
// #############################################################################
// Neo4j ships with five built-in roles. Prefer custom roles (Section 2) for
// applications; use built-ins only for human operators when appropriate.
//
// reader
//   - MATCH (TRAVERSE + READ) on all graph data
//   - No CREATE / UPDATE / DELETE of nodes or relationships
//   - No schema or DBMS administration
//
// editor
//   - Everything reader can do
//   - Plus CREATE / SET / DELETE on nodes and relationships (graph writes)
//   - Still cannot create indexes/constraints or manage databases
//
// publisher
//   - Everything editor can do
//   - Plus CREATE / DROP indexes and constraints (schema publishing)
//
// architect
//   - Everything publisher can do
//   - Plus manage databases (create/drop/alter databases in the DBMS)
//
// admin
//   - Full system access: all graph, schema, security, and DBMS privileges
//   - Equivalent to unrestricted operational control — never assign to apps
// #############################################################################

// #############################################################################
// ===== SECTION 2: CUSTOM APPLICATION ROLES =====
// #############################################################################
// Principle: grant only the privileges each workload needs (least privilege).
// Roles are created IF NOT EXISTS so this script is safe to re-run.
// #############################################################################

// --- app_finance_reader ------------------------------------------------------
// Decision: FinanceSuite only needs to read finance-adjacent entities
// (employees, departments, applications, incidents). It must not see or mutate
// Services/Databases/Servers, and must not write anything.
CREATE ROLE app_finance_reader IF NOT EXISTS;

GRANT MATCH {*} ON GRAPH neo4j ELEMENTS Employee, Department, Application, Incident TO app_finance_reader;
// For: FinanceSuite service account (read-only access to finance entities)

// --- app_dependency_writer ---------------------------------------------------
// Decision: Discovery pipeline must read the full graph to attach new infra,
// CREATE infrastructure/incident nodes, and MERGE dependency edges. It does
// not get DROP DATABASE, user management, or unrestricted WRITE on all labels.
CREATE ROLE app_dependency_writer IF NOT EXISTS;

GRANT MATCH {*} ON GRAPH neo4j TO app_dependency_writer;
GRANT CREATE ON GRAPH neo4j ELEMENTS Application, Service, Database, Server, Incident TO app_dependency_writer;
GRANT MERGE {*} ON GRAPH neo4j ELEMENTS USES, DEPENDS_ON, READS_FROM, HOSTED_ON, AFFECTS TO app_dependency_writer;
// For: pipeline that discovers and registers new infrastructure

// --- monitoring_reader -------------------------------------------------------
// Decision: Datadog (or similar) needs full-graph MATCH for topology metrics
// plus SHOW CONSTRAINT / SHOW INDEX to validate schema health. No writes.
CREATE ROLE monitoring_reader IF NOT EXISTS;

GRANT MATCH {*} ON GRAPH neo4j TO monitoring_reader;
GRANT SHOW CONSTRAINT ON DATABASE neo4j TO monitoring_reader;
GRANT SHOW INDEX ON DATABASE neo4j TO monitoring_reader;
// For: Datadog Neo4j integration service account

// --- backup_admin ------------------------------------------------------------
// Decision: Backup automation needs database management and transaction
// control on neo4j (dump/backup orchestration, kill long txs if required).
// It does not need day-to-day graph CREATE for application data.
CREATE ROLE backup_admin IF NOT EXISTS;

GRANT DATABASE MANAGEMENT ON DBMS TO backup_admin;
GRANT TRANSACTION MANAGEMENT ON DATABASE neo4j TO backup_admin;
// For: automated backup service account

// --- dba_full ----------------------------------------------------------------
// Decision: DBA team break-glass / administration role. GRANT ALL ON DBMS is
// intentionally broad. Never wire this role to application connection pools.
CREATE ROLE dba_full IF NOT EXISTS;

GRANT ALL ON DBMS TO dba_full;
// For: DBA team, never used for application connections

// #############################################################################
// ===== SECTION 3: SERVICE ACCOUNTS =====
// #############################################################################
// Passwords below are PLACEHOLDERS for local assessment only.
// In production: inject from Vault / AWS Secrets Manager (see Section 5).
// CHANGE NOT REQUIRED: service accounts authenticate non-interactively.
// #############################################################################

// --- svc_financesuite --------------------------------------------------------
CREATE USER svc_financesuite IF NOT EXISTS
SET PASSWORD 'REPLACE_FROM_VAULT_financesuite' CHANGE NOT REQUIRED;

GRANT ROLE app_finance_reader TO svc_financesuite;
// Least-privilege rationale: FinanceSuite is a consumer of finance org and
// incident context only. app_finance_reader cannot write or traverse infra
// labels it does not need, shrinking blast radius if the password leaks.

// --- svc_deploy_portal -------------------------------------------------------
CREATE USER svc_deploy_portal IF NOT EXISTS
SET PASSWORD 'REPLACE_FROM_VAULT_deploy_portal' CHANGE NOT REQUIRED;

GRANT ROLE app_dependency_writer TO svc_deploy_portal;
// Least-privilege rationale: DeployPortal's discovery job must register apps,
// services, DBs, servers, and dependency edges. It gets CREATE/MERGE on those
// elements only — not admin, not arbitrary label writes, not user management.

// --- svc_monitoring ----------------------------------------------------------
CREATE USER svc_monitoring IF NOT EXISTS
SET PASSWORD 'REPLACE_FROM_VAULT_monitoring' CHANGE NOT REQUIRED;

GRANT ROLE monitoring_reader TO svc_monitoring;
// Least-privilege rationale: Monitoring integrations are read-only observers.
// MATCH + schema SHOW is enough for health/topology scrapes; denying writes
// prevents a compromised agent from mutating production graph data.

// --- svc_backup --------------------------------------------------------------
CREATE USER svc_backup IF NOT EXISTS
SET PASSWORD 'REPLACE_FROM_VAULT_backup' CHANGE NOT REQUIRED;

GRANT ROLE backup_admin TO svc_backup;
// Least-privilege rationale: Backup tooling needs DBMS/database and
// transaction management to run consistent backups — not editor/publisher
// graph rights, and not dba_full (which would include security admin).

// Note: No service account is granted dba_full. Human DBAs receive dba_full
// (or admin) out-of-band via identity processes, never via app connection strings.

// #############################################################################
// ===== SECTION 4: VERIFICATION QUERIES =====
// #############################################################################
// Run these after setup to verify no user has more access than required.
// Cross-check each svc_* user has exactly one intended custom role.
SHOW ROLES;

SHOW USERS;

SHOW PRIVILEGES;

// #############################################################################
// ===== SECTION 5: PASSWORD POLICY COMMENTS =====
// #############################################################################
// Credentials must come from a secrets manager (HashiCorp Vault, AWS Secrets
// Manager, Azure Key Vault, etc.). Never commit real passwords to git, never
// hardcode them in application source, and never paste them into tickets.
//
// Rotation schedule:
//   - Service accounts (svc_*): rotate at least quarterly
//   - DBA / human privileged accounts: rotate at least monthly
//   - Rotate immediately on suspected compromise or staff offboarding
//
// Zero-downtime rotation procedure:
//   1. CREATE USER svc_xxx_v2 ... with the new secret from the vault
//   2. GRANT ROLE <same_role> TO svc_xxx_v2
//   3. Update application / integration config to the new username+password
//      (rolling restart / secret refresh) and verify connectivity
//   4. DROP USER svc_xxx (old) once traffic has fully cut over
// This create → cutover → delete sequence avoids a hard outage window that
// would occur if you ALTER the same user password while connections are live.
// #############################################################################
