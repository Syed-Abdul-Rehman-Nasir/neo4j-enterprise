# Enterprise Neo4j Operations Console

React 19 + Vite 8 + TypeScript frontend for the Topology Signal Room design.

## Start

```bash
npm install
cp .env.example .env
npm run dev
```

The app expects the API at `VITE_API_BASE_URL`, defaulting to `http://localhost:8000/api/v1`.

## Build and Test

```bash
npm run test
npm run build
```

## Production Container

```bash
docker build -t neo4j-ops-console .
docker run -p 8080:80 neo4j-ops-console
```
