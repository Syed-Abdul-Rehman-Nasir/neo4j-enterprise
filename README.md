# Enterprise IT Dependency Graph

This repository is a **Neo4j DBA technical assessment** built around an enterprise IT dependency graph: employees and teams use applications that depend on services, which read databases hosted on servers, with incidents overlaying the application layer for operational impact analysis. The stack is **Neo4j 5.23 Enterprise** (APOC + GDS), **Docker Compose** for local runtime, **Python 3.12+** with the official Neo4j driver and Testcontainers, plus Prometheus/Datadog monitoring stubs and GitHub Actions CI. It solves the practical DBA problem of modeling, querying, tuning, and operating a dependency graph so responders can answer “what breaks if X fails?”—and is intended for Neo4j DBA candidates, reviewers, and engineers evaluating production graph operations skill.

---

## Assessment Scoring Map

| Scoring Area | Points | Files | Status |
|---|---:|---|---|
| Schema & Cypher | 20 | `cypher/00_constraints_indexes.cypher`, `cypher/01_sample_data.cypher`, `cypher/queries/q1_finance_apps.cypher` … `q9_full_downstream_chain.cypher`, `cypher/migrations/` | Complete |
| Performance | 15 | `cypher/performance/explain_profile_analysis.cypher`, `cypher/performance/query_tuning_notes.md` | Complete |
| Python drivers / tooling | 15 | `python/neo4j_client.py`, `python/queries.py`, `python/models.py`, `python/exceptions.py`, `python/requirements.txt`, `python/__init__.py` | Complete |
| Testing | 10 | `tests/conftest.py`, `tests/test_constraints.py`, `tests/test_queries.py`, `tests/test_python_client.py`, `tests/test_performance.py`, `pytest.ini` | Complete |
| Admin / ops | 15 | `admin/backup.sh`, `admin/restore.sh`, `admin/cluster_health_check.sh`, `admin/rbac_setup.cypher`, `admin/troubleshooting_runbook.md` | Complete |
| Monitoring | 10 | `monitoring/prometheus.yml`, `monitoring/metrics_catalog.md`, `monitoring/datadog_dashboard.json`, `monitoring/datadog_alerts.json` | Complete |
| CI/CD | 5 | `ci/.github/workflows/neo4j-validate.yml`, `ci/.github/workflows/neo4j-deploy.yml` | Complete |
| Architecture docs | 10 | `architecture/SCALE_DESIGN.md`, `architecture/scale_model.cypher`, `docs/` | Complete |
| **Total** | **100** | | |

Supporting runtime (not scored separately): `docker-compose.yml`, `.env.example`, `.gitignore`.

---

## Architecture Overview

### Lab dependency graph

```
  Employees ──USES──► Applications ──DEPENDS_ON──► Services ──READS_FROM──► Databases ──HOSTED_ON──► Servers
                           ▲
                           │
                       AFFECTS
                           │
                       Incidents

  Employees ──BELONGS_TO──► Departments
```

### Production cluster topology (scale design)

```
                         ┌─────────────────────────────┐
                         │   Bolt routing (neo4j://)    │
                         └─────────────┬───────────────┘
           writes                      │               analytics / backup
              ▼                        │                        ▼
     ┌──────────────┐   Raft    ┌──────────────┐   Raft   ┌──────────────┐
     │ Core #1      │◄─────────►│ Core #2      │◄────────►│ Core #3      │
     │ PRIMARY      │           │ SECONDARY    │          │ SECONDARY    │
     └──────────────┘           └──────────────┘          └──────────────┘
              │
              ├──► Analytics Read Replica A   (blast-radius / interactive reads)
              ├──► Analytics Read Replica B   (pre-compute CronJobs)
              └──► Backup Read Replica C      (neo4j-admin backup only)
```

Details: [`architecture/SCALE_DESIGN.md`](architecture/SCALE_DESIGN.md), [`architecture/scale_model.cypher`](architecture/scale_model.cypher).

---

## Quick Start

1. **Clone and configure environment**

   ```bash
   git clone <repo-url> neo4j-enterprise-assessment
   cd neo4j-enterprise-assessment
   cp .env.example .env
   ```

   > **Warning:** `.env.example` ships with `NEO4J_PASSWORD=changeme_use_vault_in_prod`. Set a real password in `.env` before any shared or persistent environment. Do not commit `.env`.

2. **Start the environment**

   ```bash
   docker-compose up -d
   ```

   Starts Neo4j Enterprise (`:7474` Browser, `:7687` Bolt, `:2004` Prometheus metrics) and Prometheus (`:9090`).

3. **Wait for Neo4j to be healthy**

   ```bash
   docker-compose ps
   ```

   Look for `healthy` on the Neo4j service, for example:

   ```text
   NAME      IMAGE                     STATUS
   neo4j     neo4j:5.23-enterprise     Up … (healthy)
   prometheus prom/prometheus:latest   Up …
   ```

   If status is `health: starting`, wait and re-check (healthcheck allows ~40s start period).

4. **Apply schema** (constraints and indexes)

   ```bash
   docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
     < cypher/00_constraints_indexes.cypher
   ```

   On Windows PowerShell (password from `.env`):

   ```powershell
   Get-Content cypher\00_constraints_indexes.cypher -Raw |
     docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
   ```

5. **Load sample data**

   ```bash
   docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
     < cypher/01_sample_data.cypher
   ```

6. **Verify node counts**

   ```bash
   docker-compose exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
     "MATCH (n) RETURN labels(n)[0] AS label, count(n) AS cnt ORDER BY label"
   ```

   Expect labels such as `Department`, `Employee`, `Application`, `Service`, `Database`, `Server`, `Incident` with non-zero counts.

7. **Run test queries** (Browser at http://localhost:7474 or `cypher-shell`)

   **Q1 — Finance applications**

   ```cypher
   :param departmentName => 'Finance'
   ```

   Then run the production block in `cypher/queries/q1_finance_apps.cypher` (or paste the hardcoded test variant in that file). Expect FinanceSuite with multiple Finance users.

   **Q4 — Database blast radius**

   Open `cypher/queries/q4_db_impact_analysis.cypher`, set `$databaseId` to `'DB-001'`, run the production query. Expect employees/apps/services in the impact list for `fin-postgres-prod`.

   **Q5 — Bounded dependency paths**

   Open `cypher/queries/q5_dependency_paths.cypher` with `$applicationId => 'APP-001'` and `$databaseId => 'DB-001'`. Expect short DEPENDS_ON paths into the target database (no unbounded `*`).

---

## Running Tests

### Prerequisites

- **Python 3.12+**
- **Docker** running locally (Testcontainers pulls and starts Neo4j Enterprise)
- Dependencies:

  ```bash
  python -m venv .venv
  source .venv/bin/activate   # Windows: .venv\Scripts\activate
  pip install -r python/requirements.txt
  ```

### Full suite

```bash
pytest tests/ -v
```

### Individual files

| Command | What it covers |
|---|---|
| `pytest tests/test_constraints.py -v` | Uniqueness / existence constraints and index-backed seeks |
| `pytest tests/test_queries.py -v` | q1–q9 result shapes and sample expectations |
| `pytest tests/test_python_client.py -v` | Driver client, connectivity, typed query helpers |
| `pytest tests/test_performance.py -v` | EXPLAIN plans use `NodeIndexSeek` (not label scans) on hot lookups |

### How to read the output

- **PASSED** — assertion held against the Testcontainers seed graph.
- **FAILED** — diff shows expected vs actual; check seed data or query Cypher first.
- **ERROR** — often Docker/Testcontainers (daemon not running, image pull, Enterprise license env). Ensure Docker is up and you can pull `neo4j:5.23-enterprise`.
- Summary line: `N passed in Xs` means the assessment suite is green.

`pytest.ini` sets `pythonpath = .` and `testpaths = tests` so imports resolve as `python.*`.

---

## Key Design Decisions

### Why MERGE everywhere (idempotency)

Sample load and CDC-style writes use `MERGE` on unique business IDs with `ON CREATE SET` / `ON MATCH SET`, never bare `CREATE`. Re-running `01_sample_data.cypher` or replaying Kafka batches must not duplicate hubs or fail uniqueness constraints. Idempotent scripts are safe for CI, demos, and partial reloads.

### Why relationship types over generic edges

Typed edges (`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`, `OWNS`, `SUBSCRIBED_TO`) encode semantics the planner and operators can filter on. A single generic `RELATED_TO` forces property filters, pollutes degree statistics, and breaks blast-radius correctness (e.g. product lineage `EXTENDS` must not look like runtime failure coupling). See `architecture/SCALE_DESIGN.md`.

### Why typed Python dataclasses (not raw dicts)

`python/models.py` exposes frozen dataclasses with `from_record` / `to_dict`. Callers get named fields, null checks via `DataError`, and stable JSON shapes—avoiding silent key typos and `record["col"]` drift when Cypher aliases change. The driver layer stays thin; domain shape lives in models.

### Why pre-computation for blast radius at scale

At ~5M nodes / ~100M relationships, a live inbound APOC expansion plus customer fan-out targets ~**500 ms P90** with a warm cache. Tier-1 services are recomputed on a schedule (`apoc.periodic.iterate` in `architecture/scale_model.cypher`) into `blast_radius_*` properties so incident UIs pay ~**1–5 ms** for a property read, accepting bounded staleness (typically 6h) under pager load.

---

## Performance Reference

Times below are for the **lab sample graph** unless noted. Production blast-radius SLO is from the scale design.

| Query | Expected Execution Time | Index Used | Optimization Technique |
|---|---|---|---|
| Q1 Finance apps | &lt; 50 ms (sample) | Department / Application uniqueness | Selective department anchor, then expand |
| Q4 DB impact | &lt; 50 ms (sample) | `Database.databaseId` unique | Index seek + inbound expand + `DISTINCT` |
| Q5 Dependency paths | &lt; 50 ms (sample) | Application + Database unique | Bounded `DEPENDS_ON*1..3` (never unbounded `*`) |
| ID lookup (EXPLAIN tests) | &lt; 10 ms (sample) | Entity unique constraints | `NodeIndexSeek` / `NodeUniqueIndexSeek` |
| Blast radius (live, scale) | ~500 ms P90 (warm cache) | `Service.serviceId` unique | APOC `subgraphNodes` + `CALL {} IN TRANSACTIONS` |
| Blast radius (precomputed) | ~1–5 ms | `Service.serviceId` unique | Property read of `blast_radius_*` |
| Tier-1 pre-compute job | Batch / analytics replica | `Service.tier` range | `apoc.periodic.iterate` batchSize 100 |

Tuning depth: [`cypher/performance/query_tuning_notes.md`](cypher/performance/query_tuning_notes.md).

---

## Project Structure

```text
neo4j-enterprise-assessment/
├── .env.example                          # Env template (Neo4j, Datadog, backup URI)
├── .gitignore                            # Python, Neo4j data dirs, .env, IDE noise
├── README.md                             # This document
├── docker-compose.yml                    # Neo4j 5.23 Enterprise + Prometheus
├── pytest.ini                            # Pytest paths and warning filters
│
├── admin/
│   ├── backup.sh                         # Online backup helper
│   ├── restore.sh                        # Restore from backup artifact
│   ├── cluster_health_check.sh           # Raft / member health checks
│   ├── rbac_setup.cypher                 # Roles and GRANTs
│   └── troubleshooting_runbook.md        # Production incident triage
│
├── architecture/
│   ├── SCALE_DESIGN.md                   # Scale architecture (5M/100M, HA, capacity)
│   └── scale_model.cypher                # Scale schema, blast radius, pre-compute, SPOF
│
├── ci/.github/workflows/
│   ├── neo4j-validate.yml                # CI validation workflow
│   └── neo4j-deploy.yml                  # Deploy workflow stub
│
├── cypher/
│   ├── 00_constraints_indexes.cypher     # Lab uniqueness, existence, range indexes
│   ├── 01_sample_data.cypher             # Idempotent MERGE sample graph
│   ├── migrations/                       # Reserved for schema migrations
│   ├── performance/
│   │   ├── explain_profile_analysis.cypher  # EXPLAIN/PROFILE teaching queries
│   │   └── query_tuning_notes.md         # Memory, indexes, query-log reference
│   └── queries/
│       ├── q1_finance_apps.cypher        # Apps used by a department
│       ├── q2_employee_chain.cypher      # Employee → apps → services → DBs
│       ├── q3_high_incident_apps.cypher  # Apps with most incidents
│       ├── q4_db_impact_analysis.cypher  # Blast radius from a database
│       ├── q5_dependency_paths.cypher    # Bounded app→DB dependency paths
│       ├── q6_top_apps_by_users.cypher   # Top apps by distinct users
│       ├── q7_shared_db_employees.cypher # Employees sharing a database path
│       ├── q8_no_incidents.cypher        # Apps with no incident history
│       └── q9_full_downstream_chain.cypher # Full downstream dependency chain
│
├── docs/                                 # Extra documentation (placeholder)
│
├── monitoring/
│   ├── prometheus.yml                    # Scrape Neo4j :2004 metrics
│   ├── metrics_catalog.md                # Metric meanings and alert bands
│   ├── datadog_dashboard.json            # Datadog dashboard export
│   └── datadog_alerts.json               # Datadog monitor definitions
│
├── python/
│   ├── __init__.py                       # Package marker
│   ├── exceptions.py                     # Client / data error types
│   ├── models.py                         # Frozen dataclasses for query results
│   ├── neo4j_client.py                   # Driver wrapper and connectivity
│   ├── queries.py                        # Typed query helpers
│   └── requirements.txt                  # Pinned neo4j, pytest, testcontainers
│
└── tests/
    ├── __init__.py                       # Test package marker
    ├── conftest.py                       # Enterprise Testcontainers + seed fixtures
    ├── test_constraints.py               # Constraint / schema tests
    ├── test_queries.py                   # Cypher q1–q9 behavioral tests
    ├── test_python_client.py             # Python client integration tests
    └── test_performance.py               # EXPLAIN index-seek assertions
```
