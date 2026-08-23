<div align="center">

<img src="https://img.shields.io/badge/Neo4j-5.23_Enterprise-4DB33D?style=for-the-badge&logo=neo4j&logoColor=white" alt="Neo4j 5.23 Enterprise"/>
<img src="https://img.shields.io/badge/FastAPI-BFF-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"/>
<img src="https://img.shields.io/badge/React-Console-61DAFB?style=for-the-badge&logo=react&logoColor=black" alt="React"/>
<img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
<img src="https://img.shields.io/badge/Prometheus-Monitoring-E6522C?style=for-the-badge&logo=prometheus&logoColor=white" alt="Prometheus"/>

<br/><br/>

```
  Employees ──USES──► Applications ──DEPENDS_ON──► Services ──READS_FROM──► Databases ──HOSTED_ON──► Servers
                           ▲
                           │  AFFECTS
                     Incidents
```

# Enterprise IT Dependency Graph

**Graph-native blast-radius analysis for enterprise IT infrastructure.**  
Know exactly what breaks, who's affected, and how far failure propagates — before the ticket lands.

[**Quick Start**](#-quick-start) · [**Architecture**](#-architecture) · [**Console**](#-operations-console) · [**Queries**](#-key-queries) · [**Tests**](#-running-tests) · [**Performance**](#-performance-reference)

</div>

---

## The core question this system answers

> **"What breaks if X fails?"**

When an incident hits, every minute tracing dependencies costs real downtime. This platform pre-models the full dependency chain across 5M+ nodes and 100M+ relationships so the answer arrives in milliseconds — not minutes.

- Which applications go down if `DB-001` fails?
- How many employees lose access to critical tools?
- Which services are shared across the blast radius?

---

## ⚡ Quick Start

> [!WARNING]
> `.env.example` ships with `NEO4J_PASSWORD=changeme_use_vault_in_prod`. Set a real password before any shared environment. **Never commit `.env`.**

### Prerequisites

- Docker & Docker Compose
- Python 3.12+ *(optional, for local dev)*
- Node.js *(optional, for local dev)*

### Step-by-step

**1 · Clone and configure**

```bash
git clone https://github.com/Syed-Abdul-Rehman-Nasir/neo4j-enterprise neo4j-enterprise
cd neo4j-enterprise
cp .env.example .env        # then set a real NEO4J_PASSWORD
```

**2 · Start all services**

```bash
docker-compose up -d
```

| Service | Port(s) | Purpose |
|---|---|---|
| Neo4j Enterprise | `:7474` · `:7687` · `:2004` | Browser · Bolt · Prometheus metrics |
| Prometheus | `:9090` | Metrics scraping |
| FastAPI BFF | `:8000` | Query API — `/docs` for Swagger |
| Operations Console | `:8080` | React frontend |

> **Local dev only** — run data services in Docker, API and UI locally:
> ```bash
> docker-compose up -d neo4j prometheus
> python -m uvicorn python.api.main:app --reload --port 8000
> npm --prefix frontend install && npm --prefix frontend run dev
> ```
> Frontend at `http://localhost:5173`, API docs at `http://localhost:8000/docs`.

**3 · Wait for Neo4j to become healthy**

```bash
docker-compose ps    # wait for 'healthy' — allow ~40 s
```

Do not seed until you see `healthy`. `health: starting` is normal during startup.

**4 · Apply schema**

```bash
# Linux / macOS
docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  < cypher/00_constraints_indexes.cypher
```

```powershell
# Windows PowerShell
Get-Content cypher\00_constraints_indexes.cypher -Raw |
  docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
```

**5 · Load sample data**

```bash
# Linux / macOS
docker-compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  < cypher/01_sample_data.cypher
```

```powershell
# Windows PowerShell
Get-Content cypher\01_sample_data.cypher -Raw |
  docker-compose exec -T neo4j cypher-shell -u neo4j -p changeme_use_vault_in_prod
```

**6 · Verify node counts**

```bash
docker-compose exec neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  "MATCH (n) RETURN labels(n)[0] AS label, count(n) AS cnt ORDER BY label"
```

Expect **38 nodes** across `Application`, `Database`, `Department`, `Employee`, `Incident`, `Server`, `Service` — and **45 relationships**.

---

## 🏗 Architecture

### Dependency model

```
  Employees ──USES──► Applications ──DEPENDS_ON──► Services ──READS_FROM──► Databases ──HOSTED_ON──► Servers
                           ▲
                           │ AFFECTS
                           │
                       Incidents

  Employees ──BELONGS_TO──► Departments
```

Typed edges (`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`) are load-bearing — they let the query planner filter with precision and keep blast-radius traversals semantically correct. A generic `RELATED_TO` edge would silently break this.

### Production cluster topology

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

> Local Compose runs a **single-node** instance. The cluster above is the production scale design.

→ [`architecture/SCALE_DESIGN.md`](architecture/SCALE_DESIGN.md) · [`docs/HA_CLUSTERING.md`](docs/HA_CLUSTERING.md)

---

## 🖥 Operations Console

React console over a read-only FastAPI BFF. Bolt credentials never reach the browser. The Query Workbench rejects unknown query IDs and unexpected parameters.

| Route | Purpose |
|---|---|
| `/` | Live graph counts vs production scale target; DB-001 scenario |
| `/graph` | Cytoscape topology explorer |
| `/impact` | Database blast radius + dependency paths |
| `/applications` | Incidents, clean apps, downstream chain |
| `/operations` | Prometheus metrics, alerts, runbook |
| `/queries/:queryId` | Allowlisted Q1–Q9 Cypher workbench (default `/queries/q4`) |

**Suggested walkthrough:**

1. **Overview** — Review live counts and production scale strip; open the DB-001 scenario.
2. **Graph** — Explore layered topology; inspect FinanceSuite and `DEPENDS_ON` relationships.
3. **Impact** — DB-001 blast radius, impacted employees, bounded `app → database` paths. *(Simulate failure is visual only.)*
4. **Applications** — FinanceSuite incident history and weighted downstream chain; clean apps like HRConnect / AlertManager.
5. **Workbench** — Run Q4 with `DB-001`; inspect plan operators; try Q5 paths and Q7 shared-database exposure.

→ [`docs/CONSOLE.md`](docs/CONSOLE.md)

---

## 🔍 Key Queries

**Q1 — Finance department applications**
```cypher
:param departmentName => 'Finance'
// then run cypher/queries/q1_finance_apps.cypher
```

**Q4 — Database blast radius** *(the primary scenario)*
```cypher
// cypher/queries/q4_db_impact_analysis.cypher
// set $databaseId => 'DB-001'
```

**Q5 — Bounded dependency paths**
```cypher
// cypher/queries/q5_dependency_paths.cypher
// $applicationId => 'APP-001'   $databaseId => 'DB-001'
```

Run any of these from Neo4j Browser at `http://localhost:7474`, `cypher-shell`, or the Workbench UI at `/queries/q4`.

---

## 🧪 Running Tests

### Prerequisites

- Python 3.12+
- Docker running locally *(Testcontainers auto-pulls Neo4j Enterprise)*

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
pip install -r python/requirements.txt
```

### Full suite

```bash
pytest tests/ -v
pytest python/api/tests -q
npm --prefix frontend run test
```

### By file

| Command | Covers |
|---|---|
| `pytest tests/test_constraints.py -v` | Uniqueness / existence constraints and index-backed seeks |
| `pytest tests/test_queries.py -v` | Q1–Q9 result shapes and sample expectations |
| `pytest tests/test_python_client.py -v` | Driver client, connectivity, typed query helpers |
| `pytest tests/test_performance.py -v` | EXPLAIN plans confirm `NodeIndexSeek` on hot lookups |
| `pytest python/api/tests -q` | Query catalog allowlist and parameter validation |

### Reading output

| Status | Meaning |
|---|---|
| `PASSED` | Assertion held against the Testcontainers seed graph |
| `FAILED` | Diff shows expected vs actual — check seed data or Cypher first |
| `ERROR` | Usually Docker / Testcontainers — ensure daemon is running and `neo4j:5.23-enterprise` is pullable |

> `pytest.ini` sets `pythonpath = .` and `testpaths = tests` so imports resolve as `python.*`.

---

## ⚙️ Key Design Decisions

<details>
<summary><strong>MERGE everywhere — idempotency by default</strong></summary>

All writes use `MERGE` on unique business IDs with `ON CREATE SET` / `ON MATCH SET`, never bare `CREATE`. Re-running `01_sample_data.cypher` produces no duplicates and violates no constraints. This makes CI pipelines, demo resets, and partial reloads safe and repeatable.

</details>

<details>
<summary><strong>Typed relationship edges — not generic RELATED_TO</strong></summary>

`DEPENDS_ON`, `READS_FROM`, `USES`, `AFFECTS`, and scale-model types (`EXTENDS`, `OWNS`, `SUBSCRIBED_TO`) encode semantics the query planner filters on. A single generic edge type forces property filters at query time and silently breaks blast-radius correctness.

→ [`docs/GRAPH_MODEL.md`](docs/GRAPH_MODEL.md)

</details>

<details>
<summary><strong>Frozen Python dataclasses — not raw dicts</strong></summary>

`python/models.py` exposes frozen dataclasses with `from_record` / `to_dict`. Callers get named fields, null checks via `DataError`, and stable JSON shapes — eliminating silent key typos when Cypher aliases change.

</details>

<details>
<summary><strong>FastAPI BFF — browser never touches Bolt</strong></summary>

The console holds no Neo4j credentials. The BFF owns sessions, serialization, allowlisted query execution, and Prometheus proxying. Bolt stays server-side, always.

→ [`python/api/`](python/api/) · [`docs/CONSOLE.md`](docs/CONSOLE.md)

</details>

<details>
<summary><strong>Pre-computed blast radius — built for production scale</strong></summary>

At ~5M nodes / ~100M relationships, live inbound expansion targets ~500 ms P90 with a warm cache. Tier-1 services are pre-computed on a schedule into `blast_radius_*` properties so incident UIs pay ~1–5 ms per lookup — a property read, not a live traversal.

→ [`architecture/scale_model.cypher`](architecture/scale_model.cypher)

</details>

---

## 📊 Performance Reference

> Timings are for the **sample graph** unless noted. Production SLOs are from the scale design.

| Query | Target | Index | Technique |
|---|---|---|---|
| Q1 — Finance apps | `< 50 ms` | Department / Application uniqueness | Selective anchor + expand |
| Q4 — DB blast radius | `< 50 ms` | `Database.databaseId` unique | Index seek + inbound expand + `DISTINCT` |
| Q5 — Dependency paths | `< 50 ms` | Application + Database unique | Bounded `DEPENDS_ON*1..3` |
| ID lookup (EXPLAIN) | `< 10 ms` | Entity unique constraints | `NodeUniqueIndexSeek` |
| Blast radius — live (scale) | `~500 ms P90` | `Service.serviceId` unique | APOC `subgraphNodes` + `CALL {} IN TRANSACTIONS` |
| Blast radius — precomputed | `~1–5 ms` | `Service.serviceId` unique | Property read of `blast_radius_*` |
| Tier-1 pre-compute batch | Async / analytics replica | `Service.tier` range | `apoc.periodic.iterate` batchSize 100 |

→ [`cypher/performance/query_tuning_notes.md`](cypher/performance/query_tuning_notes.md) · [`docs/PERFORMANCE_ANALYSIS.md`](docs/PERFORMANCE_ANALYSIS.md)

---

## 📁 Project Structure

```text
neo4j-enterprise/
│
├── .env.example                          # Env template — Neo4j, API, Datadog, backup
├── docker-compose.yml                    # Neo4j + Prometheus + BFF + console
├── pytest.ini
│
├── admin/
│   ├── backup.sh                         # Online backup helper
│   ├── restore.sh                        # Restore from backup artifact
│   ├── cluster_health_check.sh           # Bolt / role / member health checks
│   ├── rbac_setup.cypher                 # Roles and GRANTs
│   └── troubleshooting_runbook.md        # Incident triage steps
│
├── architecture/
│   ├── SCALE_DESIGN.md                   # Scale architecture — 5M nodes / 100M rels
│   └── scale_model.cypher                # Scale schema, blast radius, pre-compute
│
├── .github/workflows/
│   ├── neo4j-validate.yml                # CI — Cypher lint, tests, frontend build
│   └── neo4j-deploy.yml                  # Manual deploy + rollback
│
├── cypher/
│   ├── 00_constraints_indexes.cypher     # Uniqueness, existence, range indexes
│   ├── 01_sample_data.cypher             # Idempotent MERGE seed (38 nodes / 45 rels)
│   ├── migrations/                       # Versioned schema migrations
│   ├── performance/
│   │   ├── explain_profile_analysis.cypher
│   │   └── query_tuning_notes.md
│   └── queries/                          # Q1–Q9 parameterized operational queries
│
├── docs/
│   ├── CONSOLE.md                        # Frontend + BFF local development guide
│   ├── GRAPH_MODEL.md                    # Modeling rationale and relationship types
│   ├── HA_CLUSTERING.md                  # High availability and clustering setup
│   └── PERFORMANCE_ANALYSIS.md          # EXPLAIN / PROFILE guidance
│
├── frontend/                             # React operations console — Vite
│   ├── src/pages/                        # Overview, Graph, Impact, Apps, Ops, Queries
│   ├── src/api/                          # Typed HTTP client for /api/v1
│   └── Dockerfile
│
├── monitoring/
│   ├── prometheus.yml                    # Scrape config for Neo4j :2004
│   ├── metrics_catalog.md                # Metric meanings and alert bands
│   ├── datadog_dashboard.json
│   └── datadog_alerts.json
│
├── python/
│   ├── api/                              # FastAPI BFF — routers, services, schemas
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

<div align="center">

Authoritative CI workflows live in [`.github/workflows/`](.github/workflows/)

<br/>

<img src="https://img.shields.io/badge/Neo4j-5.23_Enterprise-4DB33D?style=flat-square&logo=neo4j&logoColor=white"/>
<img src="https://img.shields.io/badge/APOC_%2B_GDS-enabled-4DB33D?style=flat-square"/>
<img src="https://img.shields.io/badge/Python-3.12%2B-3776AB?style=flat-square&logo=python&logoColor=white"/>
<img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"/>

</div>
