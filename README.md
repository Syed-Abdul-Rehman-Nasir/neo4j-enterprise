# 🔍 Enterprise IT Dependency Graph

> **"What breaks if X fails?"** — Real-time blast-radius analysis for enterprise IT infrastructure.

A production-grade graph platform that maps how employees, applications, services, databases, and servers interlock — and instantly surfaces the ripple effect when anything goes down.

**Stack:** Neo4j 5.23 Enterprise (APOC + GDS) · FastAPI BFF · React Operations Console · Docker Compose · Prometheus / Datadog · GitHub Actions CI

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [Architecture](#architecture)
- [Operations Console](#operations-console)
- [Quick Start](#quick-start)
- [Running Tests](#running-tests)
- [Key Design Decisions](#key-design-decisions)
- [Performance Reference](#performance-reference)
- [Project Structure](#project-structure)

---

## Why This Exists

When an incident hits, every minute spent tracing dependencies is a minute of downtime. This platform pre-models the entire dependency chain so you can answer in milliseconds:

- Which applications are affected if `DB-001` goes offline?
- How many employees lose access to critical tools?
- Which services are shared between blast-radius victims?

---

## Architecture

### Dependency Model

```
  Employees ──USES──► Applications ──DEPENDS_ON──► Services ──READS_FROM──► Databases ──HOSTED_ON──► Servers
                           ▲
                           │ AFFECTS
                           │
                       Incidents

  Employees ──BELONGS_TO──► Departments
```

Typed relationship edges (`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`) are intentional — they let the query planner filter precisely and keep blast-radius traversals correct. A generic `RELATED_TO` edge would break this.

### Production Cluster Topology

```
                         ┌─────────────────────────────┐
                         │    Bolt routing (neo4j://)   │
                         └─────────────┬───────────────┘
           writes                      │              analytics / backup
              ▼                        │                       ▼
     ┌──────────────┐   Raft    ┌──────────────┐   Raft  ┌──────────────┐
     │   Core #1    │◄─────────►│   Core #2    │◄───────►│   Core #3    │
     │   PRIMARY    │           │  SECONDARY   │         │  SECONDARY   │
     └──────────────┘           └──────────────┘         └──────────────┘
              │
              ├──► Analytics Read Replica A   (blast-radius / interactive reads)
              ├──► Analytics Read Replica B   (pre-compute CronJobs)
              └──► Backup Read Replica C      (neo4j-admin backup only)
```

> **Local dev** runs a single-node Neo4j instance via Docker Compose. The topology above is the production scale design.

Further reading: [`architecture/SCALE_DESIGN.md`](architecture/SCALE_DESIGN.md) · [`docs/HA_CLUSTERING.md`](docs/HA_CLUSTERING.md)

---

## Operations Console

A React console backed by a read-only FastAPI BFF. Bolt credentials never reach the browser. The Query Workbench rejects unknown query IDs and unexpected parameters.

| Route | Purpose |
|---|---|
| `/` | Live graph counts vs production scale target; DB-001 scenario |
| `/graph` | Cytoscape topology explorer |
| `/impact` | Database blast radius + dependency paths |
| `/applications` | Incidents, clean apps, downstream chain |
| `/operations` | Prometheus metrics, alerts, runbook |
| `/queries/:queryId` | Allowlisted Q1–Q9 Cypher workbench (default `/queries/q4`) |

### Suggested Walkthrough

1. **Overview** — Review live counts and the production scale strip; open the DB-001 scenario.
2. **Graph** — Explore layered topology; inspect FinanceSuite and `DEPENDS_ON` relationships.
3. **Impact** — DB-001 blast radius, impacted employees, and bounded `app → database` paths. ("Simulate failure" is visual only.)
4. **Applications** — FinanceSuite incident history and weighted downstream chain; clean apps like HRConnect / AlertManager.
5. **Workbench** — Run Q4 with `DB-001`; inspect expected plan operators; try Q5 paths and Q7 shared-database exposure.

Local console notes: [`docs/CONSOLE.md`](docs/CONSOLE.md)

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- (Optional for local dev) Python 3.12+, Node.js

---

### 1 · Clone and configure

```bash
git clone <repo-url> neo4j-enterprise-assessment
cd neo4j-enterprise-assessment
cp .env.example .env
```

> ⚠️ **Security:** `.env.example` ships with `NEO4J_PASSWORD=changeme_use_vault_in_prod`. **Set a real password in `.env` before any shared or persistent environment. Never commit `.env`.**

---

### 2 · Start services

```bash
docker-compose up -d
```

This starts:

| Service | Port | Purpose |
|---|---|---|
| Neo4j Enterprise | `:7474` (Browser), `:7687` (Bolt), `:2004` (Prometheus) | Graph database |
| Prometheus | `:9090` | Metrics scraping |
| FastAPI BFF | `:8000` | Query API (`/docs` for Swagger) |
| Operations Console | `:8080` | React frontend |

**Day-to-day dev** (data services only, API and UI run locally):

```powershell
docker-compose up -d neo4j prometheus

# After schema + data (steps 4–5):
python -m uvicorn python.api.main:app --reload --port 8000
npm --prefix frontend install
npm --prefix frontend run dev
```

Open `http://localhost:5173` (Vite) or `http://localhost:8080` (Compose). API docs: `http://localhost:8000/docs`.

---

### 3 · Wait for Neo4j to be healthy

```bash
docker-compose ps
```

Look for `healthy` on the Neo4j service. Status `health: starting` is normal for up to ~40 s. **Do not seed until Neo4j reports healthy.**

---

### 4 · Apply schema

```bash
# Linux / macOS
docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  < cypher/00_constraints_indexes.cypher

# Windows PowerShell
Get-Content cypher\00_constraints_indexes.cypher -Raw |
  docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
```

---

### 5 · Load sample data

```bash
# Linux / macOS
docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  < cypher/01_sample_data.cypher

# Windows PowerShell
Get-Content cypher\01_sample_data.cypher -Raw |
  docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
```

---

### 6 · Verify node counts

```bash
docker-compose exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  "MATCH (n) RETURN labels(n)[0] AS label, count(n) AS cnt ORDER BY label"
```

Expect **38 nodes** and **45 relationships** across labels: `Application`, `Database`, `Department`, `Employee`, `Incident`, `Server`, `Service`.

---

### 7 · Try key queries

**Q1 — Finance department applications**

```cypher
:param departmentName => 'Finance'
```
Then run `cypher/queries/q1_finance_apps.cypher` in Neo4j Browser or the Workbench.

**Q4 — Database blast radius**

Open `cypher/queries/q4_db_impact_analysis.cypher` and set `$databaseId` to `'DB-001'`.

**Q5 — Bounded dependency paths**

Open `cypher/queries/q5_dependency_paths.cypher` with `$applicationId => 'APP-001'` and `$databaseId => 'DB-001'`.

---

## Running Tests

### Prerequisites

- Python 3.12+
- Docker running locally (Testcontainers pulls and starts Neo4j Enterprise automatically)

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\Activate.ps1
pip install -r python/requirements.txt
```

### Run the full suite

```bash
pytest tests/ -v
pytest python/api/tests -q
npm --prefix frontend run test
```

### Individual test files

| Command | What it covers |
|---|---|
| `pytest tests/test_constraints.py -v` | Uniqueness / existence constraints and index-backed seeks |
| `pytest tests/test_queries.py -v` | Q1–Q9 result shapes and sample expectations |
| `pytest tests/test_python_client.py -v` | Driver client, connectivity, typed query helpers |
| `pytest tests/test_performance.py -v` | EXPLAIN plans confirm `NodeIndexSeek` (no label scans) on hot lookups |
| `pytest python/api/tests -q` | Query catalog allowlist and parameter validation |

### Reading test output

| Status | Meaning |
|---|---|
| `PASSED` | Assertion held against the Testcontainers seed graph |
| `FAILED` | Diff shows expected vs actual — check seed data or query Cypher first |
| `ERROR` | Usually Docker / Testcontainers (daemon not running, image pull, Enterprise license env) — ensure Docker is up and `neo4j:5.23-enterprise` is pullable |

> `pytest.ini` sets `pythonpath = .` and `testpaths = tests` so imports resolve as `python.*`.

---

## Key Design Decisions

### `MERGE` everywhere — idempotency by default

All writes use `MERGE` on unique business IDs with `ON CREATE SET` / `ON MATCH SET`, never bare `CREATE`. Re-running `01_sample_data.cypher` is safe: it will not duplicate nodes or violate constraints. This makes CI, demo resets, and partial reloads reliable.

### Typed relationship edges — not generic `RELATED_TO`

`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`, and scale-model types (`EXTENDS`, `OWNS`, `SUBSCRIBED_TO`) encode semantics the planner can filter on. A generic edge would force property filters and silently break blast-radius correctness. See [`docs/GRAPH_MODEL.md`](docs/GRAPH_MODEL.md).

### Frozen Python dataclasses — not raw dicts

`python/models.py` exposes frozen dataclasses with `from_record` / `to_dict`. Callers get named fields, null checks via `DataError`, and stable JSON shapes — eliminating silent key typos when Cypher aliases change.

### FastAPI BFF — browser never touches Bolt

The console holds no Neo4j credentials. The BFF owns sessions, serialization, allowlisted query execution, and Prometheus proxying. See [`python/api/`](python/api/) and [`docs/CONSOLE.md`](docs/CONSOLE.md).

### Pre-computed blast radius — for production scale

At ~5M nodes / ~100M relationships, a live inbound expansion targets **~500 ms P90** with a warm cache. Tier-1 services are pre-computed on a schedule into `blast_radius_*` properties so incident UIs pay **~1–5 ms** per lookup — a property read, not a traversal. See [`architecture/scale_model.cypher`](architecture/scale_model.cypher).

---

## Performance Reference

Sample-graph timings unless noted. Production SLOs are from the scale design.

| Query | Expected Time | Index Used | Technique |
|---|---|---|---|
| Q1 — Finance apps | < 50 ms | Department / Application uniqueness | Selective department anchor → expand |
| Q4 — DB impact | < 50 ms | `Database.databaseId` unique | Index seek + inbound expand + `DISTINCT` |
| Q5 — Dependency paths | < 50 ms | Application + Database unique | Bounded `DEPENDS_ON*1..3` (never unbounded `*`) |
| ID lookup (EXPLAIN tests) | < 10 ms | Entity unique constraints | `NodeIndexSeek` / `NodeUniqueIndexSeek` |
| Blast radius — live (scale) | ~500 ms P90 (warm) | `Service.serviceId` unique | APOC `subgraphNodes` + `CALL {} IN TRANSACTIONS` |
| Blast radius — precomputed | ~1–5 ms | `Service.serviceId` unique | Property read of `blast_radius_*` |
| Tier-1 pre-compute batch | Async / analytics replica | `Service.tier` range | `apoc.periodic.iterate` batchSize 100 |

Further tuning notes: [`cypher/performance/query_tuning_notes.md`](cypher/performance/query_tuning_notes.md) · [`docs/PERFORMANCE_ANALYSIS.md`](docs/PERFORMANCE_ANALYSIS.md)

---

## Project Structure

```text
neo4j-enterprise-assessment/
│
├── .env.example                          # Env template (Neo4j, API, Datadog, backup)
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
│   └── scale_model.cypher                # Scale schema, blast radius, pre-compute jobs
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
│   └── queries/                          # Parameterized operational queries Q1–Q9
│
├── docs/
│   ├── CONSOLE.md                        # Frontend + BFF local development
│   ├── GRAPH_MODEL.md                    # Modeling rationale and relationship types
│   ├── HA_CLUSTERING.md                  # High availability and clustering
│   └── PERFORMANCE_ANALYSIS.md          # EXPLAIN / PROFILE guidance
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

---

*Authoritative CI workflows live in [`.github/workflows/`](.github/workflows/).*
