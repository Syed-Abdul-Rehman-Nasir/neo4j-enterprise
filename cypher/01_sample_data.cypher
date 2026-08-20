// =============================================================================
// Sample dataset for Enterprise IT Dependency Graph
// Prerequisites: run cypher/00_constraints_indexes.cypher first
// Idempotent: all writes use MERGE + ON CREATE SET / ON MATCH SET (never CREATE)
// =============================================================================

// -----------------------------------------------------------------------------
// DEPARTMENTS (3)
// -----------------------------------------------------------------------------

MERGE (d:Department {deptId: 'DEPT-001'})
ON CREATE SET d.name = 'Finance', d.budget = 4200000, d.headcount = 18, d.costCenter = 'CC-FIN'
ON MATCH SET  d.name = 'Finance', d.budget = 4200000, d.headcount = 18, d.costCenter = 'CC-FIN';

MERGE (d:Department {deptId: 'DEPT-002'})
ON CREATE SET d.name = 'Engineering', d.budget = 9800000, d.headcount = 42, d.costCenter = 'CC-ENG'
ON MATCH SET  d.name = 'Engineering', d.budget = 9800000, d.headcount = 42, d.costCenter = 'CC-ENG';

MERGE (d:Department {deptId: 'DEPT-003'})
ON CREATE SET d.name = 'Operations', d.budget = 3100000, d.headcount = 25, d.costCenter = 'CC-OPS'
ON MATCH SET  d.name = 'Operations', d.budget = 3100000, d.headcount = 25, d.costCenter = 'CC-OPS';

// -----------------------------------------------------------------------------
// EMPLOYEES (10)
// -----------------------------------------------------------------------------

MERGE (e:Employee {employeeId: 'EMP-001'})
ON CREATE SET e.name = 'Alice Mercer', e.email = 'alice@corp.com', e.role = 'CFO', e.hireDate = date('2018-03-15')
ON MATCH SET  e.name = 'Alice Mercer', e.email = 'alice@corp.com', e.role = 'CFO', e.hireDate = date('2018-03-15');

MERGE (e:Employee {employeeId: 'EMP-002'})
ON CREATE SET e.name = 'Bob Tanaka', e.email = 'bob@corp.com', e.role = 'Financial Analyst', e.hireDate = date('2019-06-01')
ON MATCH SET  e.name = 'Bob Tanaka', e.email = 'bob@corp.com', e.role = 'Financial Analyst', e.hireDate = date('2019-06-01');

MERGE (e:Employee {employeeId: 'EMP-003'})
ON CREATE SET e.name = 'Carol Davis', e.email = 'carol@corp.com', e.role = 'Senior Engineer', e.hireDate = date('2020-01-10')
ON MATCH SET  e.name = 'Carol Davis', e.email = 'carol@corp.com', e.role = 'Senior Engineer', e.hireDate = date('2020-01-10');

MERGE (e:Employee {employeeId: 'EMP-004'})
ON CREATE SET e.name = 'Dan Okonkwo', e.email = 'dan@corp.com', e.role = 'DevOps Engineer', e.hireDate = date('2021-04-20')
ON MATCH SET  e.name = 'Dan Okonkwo', e.email = 'dan@corp.com', e.role = 'DevOps Engineer', e.hireDate = date('2021-04-20');

MERGE (e:Employee {employeeId: 'EMP-005'})
ON CREATE SET e.name = 'Eva Petrov', e.email = 'eva@corp.com', e.role = 'Accountant', e.hireDate = date('2017-09-01')
ON MATCH SET  e.name = 'Eva Petrov', e.email = 'eva@corp.com', e.role = 'Accountant', e.hireDate = date('2017-09-01');

MERGE (e:Employee {employeeId: 'EMP-006'})
ON CREATE SET e.name = 'Frank Li', e.email = 'frank@corp.com', e.role = 'SRE', e.hireDate = date('2022-02-14')
ON MATCH SET  e.name = 'Frank Li', e.email = 'frank@corp.com', e.role = 'SRE', e.hireDate = date('2022-02-14');

MERGE (e:Employee {employeeId: 'EMP-007'})
ON CREATE SET e.name = 'Grace Kim', e.email = 'grace@corp.com', e.role = 'Data Analyst', e.hireDate = date('2023-07-10')
ON MATCH SET  e.name = 'Grace Kim', e.email = 'grace@corp.com', e.role = 'Data Analyst', e.hireDate = date('2023-07-10');

MERGE (e:Employee {employeeId: 'EMP-008'})
ON CREATE SET e.name = 'Hiro Yamada', e.email = 'hiro@corp.com', e.role = 'Operations Manager', e.hireDate = date('2019-11-05')
ON MATCH SET  e.name = 'Hiro Yamada', e.email = 'hiro@corp.com', e.role = 'Operations Manager', e.hireDate = date('2019-11-05');

MERGE (e:Employee {employeeId: 'EMP-009'})
ON CREATE SET e.name = 'Isla Nair', e.email = 'isla@corp.com', e.role = 'Database Administrator', e.hireDate = date('2024-06-01')
ON MATCH SET  e.name = 'Isla Nair', e.email = 'isla@corp.com', e.role = 'Database Administrator', e.hireDate = date('2024-06-01');

MERGE (e:Employee {employeeId: 'EMP-010'})
ON CREATE SET e.name = 'Jake Cruz', e.email = 'jake@corp.com', e.role = 'Operations Lead', e.hireDate = date('2020-08-22')
ON MATCH SET  e.name = 'Jake Cruz', e.email = 'jake@corp.com', e.role = 'Operations Lead', e.hireDate = date('2020-08-22');

// -----------------------------------------------------------------------------
// APPLICATIONS (5)
// -----------------------------------------------------------------------------

MERGE (a:Application {applicationId: 'APP-001'})
ON CREATE SET a.name = 'FinanceSuite', a.version = '4.2.1', a.owner = 'Finance', a.tier = 1, a.description = 'Core finance and accounting platform'
ON MATCH SET  a.name = 'FinanceSuite', a.version = '4.2.1', a.owner = 'Finance', a.tier = 1, a.description = 'Core finance and accounting platform';

MERGE (a:Application {applicationId: 'APP-002'})
ON CREATE SET a.name = 'DeployPortal', a.version = '2.0.0', a.owner = 'Engineering', a.tier = 2, a.description = 'Deployment and release management portal'
ON MATCH SET  a.name = 'DeployPortal', a.version = '2.0.0', a.owner = 'Engineering', a.tier = 2, a.description = 'Deployment and release management portal';

MERGE (a:Application {applicationId: 'APP-003'})
ON CREATE SET a.name = 'HRConnect', a.version = '1.8.3', a.owner = 'Operations', a.tier = 2, a.description = 'HR and workforce operations portal'
ON MATCH SET  a.name = 'HRConnect', a.version = '1.8.3', a.owner = 'Operations', a.tier = 2, a.description = 'HR and workforce operations portal';

MERGE (a:Application {applicationId: 'APP-004'})
ON CREATE SET a.name = 'DataLakeDash', a.version = '3.1.0', a.owner = 'Engineering', a.tier = 1, a.description = 'Data lake analytics and dashboarding'
ON MATCH SET  a.name = 'DataLakeDash', a.version = '3.1.0', a.owner = 'Engineering', a.tier = 1, a.description = 'Data lake analytics and dashboarding';

MERGE (a:Application {applicationId: 'APP-005'})
ON CREATE SET a.name = 'AlertManager', a.version = '1.0.5', a.owner = 'Operations', a.tier = 3, a.description = 'Alert routing and notification management'
ON MATCH SET  a.name = 'AlertManager', a.version = '1.0.5', a.owner = 'Operations', a.tier = 3, a.description = 'Alert routing and notification management';

// -----------------------------------------------------------------------------
// SERVICES (6)
// -----------------------------------------------------------------------------

MERGE (s:Service {serviceId: 'SVC-001'})
ON CREATE SET s.name = 'auth-service', s.type = 'REST', s.port = 8080, s.protocol = 'HTTP/2', s.sla_ms = 200
ON MATCH SET  s.name = 'auth-service', s.type = 'REST', s.port = 8080, s.protocol = 'HTTP/2', s.sla_ms = 200;

MERGE (s:Service {serviceId: 'SVC-002'})
ON CREATE SET s.name = 'reporting-svc', s.type = 'REST', s.port = 8081, s.protocol = 'HTTP/1.1', s.sla_ms = 5000
ON MATCH SET  s.name = 'reporting-svc', s.type = 'REST', s.port = 8081, s.protocol = 'HTTP/1.1', s.sla_ms = 5000;

MERGE (s:Service {serviceId: 'SVC-003'})
ON CREATE SET s.name = 'pipeline-worker', s.type = 'gRPC', s.port = 50051, s.protocol = 'gRPC', s.sla_ms = 1000
ON MATCH SET  s.name = 'pipeline-worker', s.type = 'gRPC', s.port = 50051, s.protocol = 'gRPC', s.sla_ms = 1000;

MERGE (s:Service {serviceId: 'SVC-004'})
ON CREATE SET s.name = 'notification-svc', s.type = 'queue', s.port = 5672, s.protocol = 'AMQP', s.sla_ms = 30000
ON MATCH SET  s.name = 'notification-svc', s.type = 'queue', s.port = 5672, s.protocol = 'AMQP', s.sla_ms = 30000;

MERGE (s:Service {serviceId: 'SVC-005'})
ON CREATE SET s.name = 'data-ingest', s.type = 'gRPC', s.port = 50052, s.protocol = 'gRPC', s.sla_ms = 500
ON MATCH SET  s.name = 'data-ingest', s.type = 'gRPC', s.port = 50052, s.protocol = 'gRPC', s.sla_ms = 500;

MERGE (s:Service {serviceId: 'SVC-006'})
ON CREATE SET s.name = 'search-api', s.type = 'REST', s.port = 9200, s.protocol = 'HTTP/1.1', s.sla_ms = 300
ON MATCH SET  s.name = 'search-api', s.type = 'REST', s.port = 9200, s.protocol = 'HTTP/1.1', s.sla_ms = 300;

// -----------------------------------------------------------------------------
// DATABASES (3)
// -----------------------------------------------------------------------------

MERGE (db:Database {databaseId: 'DB-001'})
ON CREATE SET db.name = 'fin-postgres-prod', db.engine = 'PostgreSQL', db.version = '15.4', db.size_gb = 480, db.env = 'production', db.replication = 'synchronous'
ON MATCH SET  db.name = 'fin-postgres-prod', db.engine = 'PostgreSQL', db.version = '15.4', db.size_gb = 480, db.env = 'production', db.replication = 'synchronous';

MERGE (db:Database {databaseId: 'DB-002'})
ON CREATE SET db.name = 'ops-mongo-prod', db.engine = 'MongoDB', db.version = '6.0.8', db.size_gb = 220, db.env = 'production', db.replication = 'async'
ON MATCH SET  db.name = 'ops-mongo-prod', db.engine = 'MongoDB', db.version = '6.0.8', db.size_gb = 220, db.env = 'production', db.replication = 'async';

MERGE (db:Database {databaseId: 'DB-003'})
ON CREATE SET db.name = 'datalake-pg-prod', db.engine = 'PostgreSQL', db.version = '15.4', db.size_gb = 1200, db.env = 'production', db.replication = 'synchronous'
ON MATCH SET  db.name = 'datalake-pg-prod', db.engine = 'PostgreSQL', db.version = '15.4', db.size_gb = 1200, db.env = 'production', db.replication = 'synchronous';

// -----------------------------------------------------------------------------
// SERVERS (3)
// -----------------------------------------------------------------------------

MERGE (srv:Server {serverId: 'SRV-001'})
ON CREATE SET srv.name = 'db-primary-east', srv.ip = '10.0.1.10', srv.region = 'us-east-1', srv.az = 'us-east-1a', srv.os = 'RHEL 9', srv.cpu_cores = 32, srv.ram_gb = 256
ON MATCH SET  srv.name = 'db-primary-east', srv.ip = '10.0.1.10', srv.region = 'us-east-1', srv.az = 'us-east-1a', srv.os = 'RHEL 9', srv.cpu_cores = 32, srv.ram_gb = 256;

MERGE (srv:Server {serverId: 'SRV-002'})
ON CREATE SET srv.name = 'app-server-west', srv.ip = '10.0.2.20', srv.region = 'us-west-2', srv.az = 'us-west-2b', srv.os = 'Ubuntu 22', srv.cpu_cores = 16, srv.ram_gb = 128
ON MATCH SET  srv.name = 'app-server-west', srv.ip = '10.0.2.20', srv.region = 'us-west-2', srv.az = 'us-west-2b', srv.os = 'Ubuntu 22', srv.cpu_cores = 16, srv.ram_gb = 128;

MERGE (srv:Server {serverId: 'SRV-003'})
ON CREATE SET srv.name = 'data-cluster-eu', srv.ip = '10.1.0.30', srv.region = 'eu-west-1', srv.az = 'eu-west-1c', srv.os = 'RHEL 9', srv.cpu_cores = 64, srv.ram_gb = 512
ON MATCH SET  srv.name = 'data-cluster-eu', srv.ip = '10.1.0.30', srv.region = 'eu-west-1', srv.az = 'eu-west-1c', srv.os = 'RHEL 9', srv.cpu_cores = 64, srv.ram_gb = 512;

// -----------------------------------------------------------------------------
// INCIDENTS (8)
// -----------------------------------------------------------------------------

MERGE (i:Incident {incidentId: 'INC-001'})
ON CREATE SET i.title = 'Auth timeout spike', i.severity = 'P1', i.status = 'resolved', i.ts = datetime('2025-01-10T09:22:00'), i.resolvedTs = datetime('2025-01-10T10:45:00'), i.mttr_minutes = 83
ON MATCH SET  i.title = 'Auth timeout spike', i.severity = 'P1', i.status = 'resolved', i.ts = datetime('2025-01-10T09:22:00'), i.resolvedTs = datetime('2025-01-10T10:45:00'), i.mttr_minutes = 83;

MERGE (i:Incident {incidentId: 'INC-002'})
ON CREATE SET i.title = 'Report generation OOM', i.severity = 'P2', i.status = 'resolved', i.ts = datetime('2025-01-14T14:05:00'), i.resolvedTs = datetime('2025-01-14T17:20:00'), i.mttr_minutes = 195
ON MATCH SET  i.title = 'Report generation OOM', i.severity = 'P2', i.status = 'resolved', i.ts = datetime('2025-01-14T14:05:00'), i.resolvedTs = datetime('2025-01-14T17:20:00'), i.mttr_minutes = 195;

MERGE (i:Incident {incidentId: 'INC-003'})
ON CREATE SET i.title = 'DB connection pool exhausted', i.severity = 'P1', i.status = 'open', i.ts = datetime('2025-02-01T07:11:00'), i.resolvedTs = null, i.mttr_minutes = null
ON MATCH SET  i.title = 'DB connection pool exhausted', i.severity = 'P1', i.status = 'open', i.ts = datetime('2025-02-01T07:11:00'), i.resolvedTs = null, i.mttr_minutes = null;

MERGE (i:Incident {incidentId: 'INC-004'})
ON CREATE SET i.title = 'Pipeline dead-letter queue full', i.severity = 'P2', i.status = 'investigating', i.ts = datetime('2025-02-03T11:48:00'), i.resolvedTs = null, i.mttr_minutes = null
ON MATCH SET  i.title = 'Pipeline dead-letter queue full', i.severity = 'P2', i.status = 'investigating', i.ts = datetime('2025-02-03T11:48:00'), i.resolvedTs = null, i.mttr_minutes = null;

MERGE (i:Incident {incidentId: 'INC-005'})
ON CREATE SET i.title = 'Slow finance dashboard', i.severity = 'P3', i.status = 'resolved', i.ts = datetime('2025-02-05T16:30:00'), i.resolvedTs = datetime('2025-02-05T17:10:00'), i.mttr_minutes = 40
ON MATCH SET  i.title = 'Slow finance dashboard', i.severity = 'P3', i.status = 'resolved', i.ts = datetime('2025-02-05T16:30:00'), i.resolvedTs = datetime('2025-02-05T17:10:00'), i.mttr_minutes = 40;

MERGE (i:Incident {incidentId: 'INC-006'})
ON CREATE SET i.title = 'Auth token TTL misconfigured', i.severity = 'P2', i.status = 'resolved', i.ts = datetime('2025-02-10T08:00:00'), i.resolvedTs = datetime('2025-02-10T09:30:00'), i.mttr_minutes = 90
ON MATCH SET  i.title = 'Auth token TTL misconfigured', i.severity = 'P2', i.status = 'resolved', i.ts = datetime('2025-02-10T08:00:00'), i.resolvedTs = datetime('2025-02-10T09:30:00'), i.mttr_minutes = 90;

MERGE (i:Incident {incidentId: 'INC-007'})
ON CREATE SET i.title = 'FinanceSuite login failures', i.severity = 'P1', i.status = 'resolved', i.ts = datetime('2025-02-18T20:55:00'), i.resolvedTs = datetime('2025-02-18T22:10:00'), i.mttr_minutes = 75
ON MATCH SET  i.title = 'FinanceSuite login failures', i.severity = 'P1', i.status = 'resolved', i.ts = datetime('2025-02-18T20:55:00'), i.resolvedTs = datetime('2025-02-18T22:10:00'), i.mttr_minutes = 75;

MERGE (i:Incident {incidentId: 'INC-008'})
ON CREATE SET i.title = 'DataLake ingest lag', i.severity = 'P3', i.status = 'open', i.ts = datetime('2025-02-22T13:07:00'), i.resolvedTs = null, i.mttr_minutes = null
ON MATCH SET  i.title = 'DataLake ingest lag', i.severity = 'P3', i.status = 'open', i.ts = datetime('2025-02-22T13:07:00'), i.resolvedTs = null, i.mttr_minutes = null;

// -----------------------------------------------------------------------------
// BELONGS_TO (Employee → Department)
// -----------------------------------------------------------------------------

MATCH (e:Employee {employeeId: 'EMP-001'}), (d:Department {deptId: 'DEPT-001'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-002'}), (d:Department {deptId: 'DEPT-001'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-003'}), (d:Department {deptId: 'DEPT-002'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-004'}), (d:Department {deptId: 'DEPT-002'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-005'}), (d:Department {deptId: 'DEPT-001'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-006'}), (d:Department {deptId: 'DEPT-003'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-007'}), (d:Department {deptId: 'DEPT-001'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-008'}), (d:Department {deptId: 'DEPT-003'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-009'}), (d:Department {deptId: 'DEPT-002'})
MERGE (e)-[:BELONGS_TO]->(d);

MATCH (e:Employee {employeeId: 'EMP-010'}), (d:Department {deptId: 'DEPT-003'})
MERGE (e)-[:BELONGS_TO]->(d);

// -----------------------------------------------------------------------------
// USES (Employee → Application) with since
// -----------------------------------------------------------------------------

MATCH (e:Employee {employeeId: 'EMP-001'}), (a:Application {applicationId: 'APP-001'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2023-01-01'
ON MATCH SET  r.since = '2023-01-01';

MATCH (e:Employee {employeeId: 'EMP-001'}), (a:Application {applicationId: 'APP-004'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2024-03-01'
ON MATCH SET  r.since = '2024-03-01';

MATCH (e:Employee {employeeId: 'EMP-002'}), (a:Application {applicationId: 'APP-001'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2022-06-15'
ON MATCH SET  r.since = '2022-06-15';

MATCH (e:Employee {employeeId: 'EMP-005'}), (a:Application {applicationId: 'APP-001'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2021-09-01'
ON MATCH SET  r.since = '2021-09-01';

MATCH (e:Employee {employeeId: 'EMP-007'}), (a:Application {applicationId: 'APP-001'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2023-07-10'
ON MATCH SET  r.since = '2023-07-10';

MATCH (e:Employee {employeeId: 'EMP-003'}), (a:Application {applicationId: 'APP-002'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2024-01-01'
ON MATCH SET  r.since = '2024-01-01';

MATCH (e:Employee {employeeId: 'EMP-004'}), (a:Application {applicationId: 'APP-002'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2024-01-01'
ON MATCH SET  r.since = '2024-01-01';

MATCH (e:Employee {employeeId: 'EMP-006'}), (a:Application {applicationId: 'APP-005'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2023-11-01'
ON MATCH SET  r.since = '2023-11-01';

MATCH (e:Employee {employeeId: 'EMP-008'}), (a:Application {applicationId: 'APP-003'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2023-03-20'
ON MATCH SET  r.since = '2023-03-20';

MATCH (e:Employee {employeeId: 'EMP-009'}), (a:Application {applicationId: 'APP-004'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2024-06-01'
ON MATCH SET  r.since = '2024-06-01';

MATCH (e:Employee {employeeId: 'EMP-010'}), (a:Application {applicationId: 'APP-003'})
MERGE (e)-[r:USES]->(a)
ON CREATE SET r.since = '2022-12-01'
ON MATCH SET  r.since = '2022-12-01';

// -----------------------------------------------------------------------------
// DEPENDS_ON (Application → Service) with weight
// -----------------------------------------------------------------------------

MATCH (a:Application {applicationId: 'APP-001'}), (s:Service {serviceId: 'SVC-001'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 1.0
ON MATCH SET  r.weight = 1.0;

MATCH (a:Application {applicationId: 'APP-001'}), (s:Service {serviceId: 'SVC-002'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 0.8
ON MATCH SET  r.weight = 0.8;

MATCH (a:Application {applicationId: 'APP-002'}), (s:Service {serviceId: 'SVC-003'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 1.0
ON MATCH SET  r.weight = 1.0;

MATCH (a:Application {applicationId: 'APP-003'}), (s:Service {serviceId: 'SVC-004'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 0.9
ON MATCH SET  r.weight = 0.9;

MATCH (a:Application {applicationId: 'APP-004'}), (s:Service {serviceId: 'SVC-005'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 1.0
ON MATCH SET  r.weight = 1.0;

MATCH (a:Application {applicationId: 'APP-004'}), (s:Service {serviceId: 'SVC-006'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 0.7
ON MATCH SET  r.weight = 0.7;

MATCH (a:Application {applicationId: 'APP-005'}), (s:Service {serviceId: 'SVC-004'})
MERGE (a)-[r:DEPENDS_ON]->(s)
ON CREATE SET r.weight = 0.6
ON MATCH SET  r.weight = 0.6;

// -----------------------------------------------------------------------------
// READS_FROM (Service → Database)
// -----------------------------------------------------------------------------

MATCH (s:Service {serviceId: 'SVC-001'}), (db:Database {databaseId: 'DB-001'})
MERGE (s)-[:READS_FROM]->(db);

MATCH (s:Service {serviceId: 'SVC-002'}), (db:Database {databaseId: 'DB-001'})
MERGE (s)-[:READS_FROM]->(db);

MATCH (s:Service {serviceId: 'SVC-003'}), (db:Database {databaseId: 'DB-002'})
MERGE (s)-[:READS_FROM]->(db);

MATCH (s:Service {serviceId: 'SVC-004'}), (db:Database {databaseId: 'DB-002'})
MERGE (s)-[:READS_FROM]->(db);

MATCH (s:Service {serviceId: 'SVC-005'}), (db:Database {databaseId: 'DB-003'})
MERGE (s)-[:READS_FROM]->(db);

MATCH (s:Service {serviceId: 'SVC-006'}), (db:Database {databaseId: 'DB-003'})
MERGE (s)-[:READS_FROM]->(db);

// -----------------------------------------------------------------------------
// HOSTED_ON (Database → Server)
// -----------------------------------------------------------------------------

MATCH (db:Database {databaseId: 'DB-001'}), (srv:Server {serverId: 'SRV-001'})
MERGE (db)-[:HOSTED_ON]->(srv);

MATCH (db:Database {databaseId: 'DB-002'}), (srv:Server {serverId: 'SRV-002'})
MERGE (db)-[:HOSTED_ON]->(srv);

MATCH (db:Database {databaseId: 'DB-003'}), (srv:Server {serverId: 'SRV-003'})
MERGE (db)-[:HOSTED_ON]->(srv);

// -----------------------------------------------------------------------------
// AFFECTS (Incident → Application)
// -----------------------------------------------------------------------------

MATCH (i:Incident {incidentId: 'INC-001'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-002'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-003'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-004'}), (a:Application {applicationId: 'APP-002'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-005'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-006'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-007'}), (a:Application {applicationId: 'APP-001'})
MERGE (i)-[:AFFECTS]->(a);

MATCH (i:Incident {incidentId: 'INC-008'}), (a:Application {applicationId: 'APP-004'})
MERGE (i)-[:AFFECTS]->(a);

// -----------------------------------------------------------------------------
// VERIFICATION (run manually; expected counts)
// -----------------------------------------------------------------------------
// MATCH (n:Department) RETURN count(n) -- expected: 3
// MATCH (n:Employee) RETURN count(n) -- expected: 10
// MATCH (n:Application) RETURN count(n) -- expected: 5
// MATCH (n:Service) RETURN count(n) -- expected: 6
// MATCH (n:Database) RETURN count(n) -- expected: 3
// MATCH (n:Server) RETURN count(n) -- expected: 3
// MATCH (n:Incident) RETURN count(n) -- expected: 8
// MATCH ()-[r]->() RETURN type(r), count(r) ORDER BY type(r)
