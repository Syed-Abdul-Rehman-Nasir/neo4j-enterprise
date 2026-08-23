# Operations Console

React + FastAPI console for the Neo4j enterprise assessment graph.

## Local development

```powershell
docker-compose up -d neo4j prometheus
# seed schema + sample data via cypher-shell (see root README)
python -m uvicorn python.api.main:app --reload --port 8000
npm --prefix frontend install
npm --prefix frontend run dev
```

- UI: http://localhost:5173
- API: http://localhost:8000/api/v1/health
- OpenAPI: http://localhost:8000/docs

Frontend env: `frontend/.env.example` → copy to `.env.local` with `VITE_API_BASE_URL`.

## Security model

- Browser talks only to the FastAPI BFF.
- BFF is read-only except `POST /api/v1/queries/{id}/execute` for allowlisted Q1–Q9.
- No Bolt credentials in `VITE_*` variables.
- Backup/restore/kill are documentation/runbook only — never triggered from the UI.
