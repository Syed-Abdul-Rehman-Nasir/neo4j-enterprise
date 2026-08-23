# Enterprise IT Dependency Graph

Neo4j-backed operations platform for enterprise IT dependency and blast-radius analysis. Employees and teams use applications that depend on services, which read databases hosted on servers, with incidents overlaying the application layer. The stack is **Neo4j 5.23 Enterprise** (APOC + GDS), **Docker Compose**, a **FastAPI** BFF over the official Neo4j Python driver, a **React** operations console, Prometheus/Datadog monitoring artifacts, and GitHub Actions CI.

**Primary question this system answers:** “What breaks if X fails?”

---

## Operations Console

React console over a read-only FastAPI BFF. Six views:

| Route | Purpose |
|---|---|
| `/` | Live graph counts vs production scale target; DB-001 scenario |
| `/graph` | Cytoscape topology explorer |
| `/impact` | Database blast radius + dependency paths |
| `/applications` | Incidents, clean apps, downstream chain |
| `/operations` | Prometheus metrics, alerts, runbook |
| `/queries/:queryId` | Allowlisted Q1–Q9 Cypher workbench (default `/queries/q4`) |

### Walkthrough

1. **Overview** — review live counts and the separate production scale strip; open the DB-001 scenario.
2. **Graph** — explore layered topology; inspect FinanceSuite and `DEPENDS_ON` relationships.
3. **Impact** — DB-001 blast radius, impacted employees, and bounded app→database paths; Simulate failure is visual only.
4. **Applications** — FinanceSuite incident history and weighted downstream chain; clean applications (e.g. HRConnect / AlertManager).
5. **Workbench** — run Q4 with `DB-001`; inspect expected plan operators; try Q5 paths and Q7 shared-database exposure.

Bolt credentials are never exposed to the browser. Query Workbench rejects unknown query IDs and unexpected parameters.

Local console notes: [`docs/CONSOLE.md`](docs/CONSOLE.md).

---

## Architecture Overview

### Dependency graph

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

Details: [`architecture/SCALE_DESIGN.md`](architecture/SCALE_DESIGN.md), [`architecture/scale_model.cypher`](architecture/scale_model.cypher), [`docs/HA_CLUSTERING.md`](docs/HA_CLUSTERING.md).

Local Compose runs a **single-node** Neo4j instance for development. The multi-node topology above is the production scale design.

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

   Starts Neo4j Enterprise (`:7474` Browser, `:7687` Bolt, `:2004` Prometheus metrics), Prometheus (`:9090`), the FastAPI BFF (`:8000`), and the Operations Console frontend (`:8080`).

   For day-to-day development you can also run only data services and start API/UI locally:

   ```powershell
   docker-compose up -d neo4j prometheus
   # after schema + sample data (steps 4–5):
   python -m uvicorn python.api.main:app --reload --port 8000
   npm --prefix frontend install
   npm --prefix frontend run dev
   ```

   Open `http://localhost:5173` (Vite) or `http://localhost:8080` (Compose frontend). API docs: `http://localhost:8000/docs`.

3. **Wait for Neo4j to be healthy**

   ```bash
   docker-compose ps
   ```

   Look for `healthy` on the Neo4j service. If status is `health: starting`, wait and re-check (healthcheck allows ~40s start period). Do not seed until Neo4j is healthy.

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

   PowerShell:

   ```powershell
   Get-Content cypher\01_sample_data.cypher -Raw |
     docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
   ```

6. **Verify node counts**

   ```bash
   docker-compose exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
     "MATCH (n) RETURN labels(n)[0] AS label, count(n) AS cnt ORDER BY label"
   ```

   Expect labels such as `Department`, `Employee`, `Application`, `Service`, `Database`, `Server`, `Incident` with non-zero counts (sample graph: **38 nodes**, **45 relationships**).

7. **Try queries** (Browser at http://localhost:7474, `cypher-shell`, or the Workbench UI)

   **Q1 — Finance applications**

   ```cypher
   :param departmentName => 'Finance'
   ```

   Then run the production block in `cypher/queries/q1_finance_apps.cypher`.

   **Q4 — Database blast radius**

   Open `cypher/queries/q4_db_impact_analysis.cypher`, set `$databaseId` to `'DB-001'`.

   **Q5 — Bounded dependency paths**

   Open `cypher/queries/q5_dependency_paths.cypher` with `$applicationId => 'APP-001'` and `$databaseId => 'DB-001'`.

---

## Running Tests

### Prerequisites

- **Python 3.12+**
- **Docker** running locally (Testcontainers pulls and starts Neo4j Enterprise)
- Dependencies:

  ```bash
  python -m venv .venv
  source .venv/bin/activate   # Windows: .venv\Scripts\Activate.ps1
  pip install -r python/requirements.txt
  ```

### Full suite

```bash
pytest tests/ -v
pytest python/api/tests -q
npm --prefix frontend run test
```

### Individual files

| Command | What it covers |
|---|---|
| `pytest tests/test_constraints.py -v` | Uniqueness / existence constraints and index-backed seeks |
| `pytest tests/test_queries.py -v` | q1–q9 result shapes and sample expectations |
| `pytest tests/test_python_client.py -v` | Driver client, connectivity, typed query helpers |
| `pytest tests/test_performance.py -v` | EXPLAIN plans use `NodeIndexSeek` (not label scans) on hot lookups |
| `pytest python/api/tests -q` | Query catalog allowlist and parameter validation |

### How to read the output

- **PASSED** — assertion held against the Testcontainers seed graph.
- **FAILED** — diff shows expected vs actual; check seed data or query Cypher first.
- **ERROR** — often Docker/Testcontainers (daemon not running, image pull, Enterprise license env). Ensure Docker is up and you can pull `neo4j:5.23-enterprise`.

`pytest.ini` sets `pythonpath = .` and `testpaths = tests` so imports resolve as `python.*`.

---

## Key Design Decisions

### Why MERGE everywhere (idempotency)

Sample load and CDC-style writes use `MERGE` on unique business IDs with `ON CREATE SET` / `ON MATCH SET`, never bare `CREATE`. Re-running `01_sample_data.cypher` must not duplicate hubs or fail uniqueness constraints. Idempotent scripts are safe for CI, demos, and partial reloads.

### Why relationship types over generic edges

Typed edges (`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`, and scale-model `EXTENDS` / `OWNS` / `SUBSCRIBED_TO`) encode semantics the planner can filter on. A single generic `RELATED_TO` forces property filters and breaks blast-radius correctness. See `architecture/SCALE_DESIGN.md` and `docs/GRAPH_MODEL.md`.

### Why typed Python dataclasses (not raw dicts)

`python/models.py` exposes frozen dataclasses with `from_record` / `to_dict`. Callers get named fields, null checks via `DataError`, and stable JSON shapes—avoiding silent key typos when Cypher aliases change.

### Why a FastAPI BFF (not browser → Bolt)

The console never holds Neo4j credentials. The BFF owns sessions, serialization, allowlisted query execution, and Prometheus proxying. See `python/api/` and `docs/CONSOLE.md`.

### Why pre-computation for blast radius at scale

At ~5M nodes / ~100M relationships, a live inbound expansion plus customer fan-out targets ~**500 ms P90** with a warm cache. Tier-1 services can be recomputed on a schedule into `blast_radius_*` properties so incident UIs pay ~**1–5 ms** for a property read. See `architecture/scale_model.cypher`.

---

## Performance Reference

Times below are for the **sample graph** unless noted. Production blast-radius SLO is from the scale design.

| Query | Expected Execution Time | Index Used | Optimization Technique |
|---|---|---|---|
| Q1 Finance apps | &lt; 50 ms (sample) | Department / Application uniqueness | Selective department anchor, then expand |
| Q4 DB impact | &lt; 50 ms (sample) | `Database.databaseId` unique | Index seek + inbound expand + `DISTINCT` |
| Q5 Dependency paths | &lt; 50 ms (sample) | Application + Database unique | Bounded `DEPENDS_ON*1..3` (never unbounded `*`) |
| ID lookup (EXPLAIN tests) | &lt; 10 ms (sample) | Entity unique constraints | `NodeIndexSeek` / `NodeUniqueIndexSeek` |
| Blast radius (live, scale) | ~500 ms P90 (warm cache) | `Service.serviceId` unique | APOC `subgraphNodes` + `CALL {} IN TRANSACTIONS` |
| Blast radius (precomputed) | ~1–5 ms | `Service.serviceId` unique | Property read of `blast_radius_*` |
| Tier-1 pre-compute job | Batch / analytics replica | `Service.tier` range | `apoc.periodic.iterate` batchSize 100 |

Tuning depth: [`cypher/performance/query_tuning_notes.md`](cypher/performance/query_tuning_notes.md), [`docs/PERFORMANCE_ANALYSIS.md`](docs/PERFORMANCE_ANALYSIS.md).

---

## Project Structure

```text
neo4j-enterprise-assessment/
├── .env.example                          # Env template (Neo4j, API, Datadog, backup)
├── .gitignore
├── README.md                             # This document
├── docker-compose.yml                    # Neo4j + Prometheus + API + frontend
├── pytest.ini
│
├── admin/
│   ├── backup.sh                         # Online backup helper
│   ├── restore.sh                        # Restore from backup artifact
│   ├── cluster_health_check.sh           # Bolt / role / member health checks
│   ├── rbac_setup.cypher                 # Roles and GRANTs
│   └── troubleshooting_runbook.md        # Incident triage
│
├── architecture/
│   ├── SCALE_DESIGN.md                   # Scale architecture (5M/100M, HA, capacity)
│   └── scale_model.cypher                # Scale schema, blast radius, pre-compute
│
├── .github/workflows/
│   ├── neo4j-validate.yml                # CI: Cypher lint, Neo4j tests, frontend build
│   └── neo4j-deploy.yml                  # Manual production deploy + rollback
│
├── cypher/
│   ├── 00_constraints_indexes.cypher     # Uniqueness, existence, range indexes
│   ├── 01_sample_data.cypher             # Idempotent MERGE sample graph
│   ├── migrations/                       # Versioned schema migrations
│   ├── performance/
│   │   ├── explain_profile_analysis.cypher
│   │   └── query_tuning_notes.md
│   └── queries/                          # Parameterized operational queries q1–q9
│
├── docs/
│   ├── CONSOLE.md                        # Frontend + BFF local development
│   ├── GRAPH_MODEL.md                    # Modeling notes
│   ├── HA_CLUSTERING.md                  # High availability & clustering
│   └── PERFORMANCE_ANALYSIS.md           # EXPLAIN/PROFILE guidance
│
├── frontend/                             # React operations console (Vite)
│   ├── src/pages/                        # Overview, Graph, Impact, Apps, Ops, Queries
│   ├── src/api/                          # Typed HTTP client for /api/v1
│   └── Dockerfile
│
├── monitoring/
│   ├── prometheus.yml                    # Scrape Neo4j :2004 metrics
│   ├── metrics_catalog.md                # Metric meanings and alert bands
│   ├── datadog_dashboard.json            # Datadog dashboard export
│   └── datadog_alerts.json               # Datadog monitor definitions
│
├── python/
│   ├── api/                              # FastAPI BFF (routers, services, schemas)
│   ├── neo4j_client.py                   # Driver wrapper
│   ├── queries.py                        # Typed query helpers
│   ├── models.py                         # Frozen result dataclasses
│   ├── exceptions.py                     # Client / data error types
│   └── requirements.txt
│
└── tests/
    ├── conftest.py                       # Testcontainers Neo4j + seed fixtures
    ├── test_constraints.py
    ├── test_queries.py
    ├── test_python_client.py
    └── test_performance.py
```

Authoritative CI workflows live in `.github/workflows/`.
