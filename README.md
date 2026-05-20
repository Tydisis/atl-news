# atl-news

Unified RSS news feed covering Atlanta local news, Georgia state politics, and US national politics.

A FastAPI read-only API serves articles from a store. A separate fetcher process polls RSS feeds on a schedule, normalizes them into a single schema, and writes to that store. A React + Vite SPA consumes `/api/feed`.

## Architecture

```
                CloudFront
              ┌──────┴──────┐
       /api/* │             │ /
              ▼             ▼
            ALB           S3 (SPA)
              │
              ▼
        ECS Fargate ────► DynamoDB ◄──── ECS Fargate (scheduled)
        api service       articles       fetcher task
                                         (EventBridge cron)
```

Same Docker image powers two ECS task definitions:

- `api` (long-running service, behind ALB) → reads from DynamoDB
- `fetcher` (one-shot scheduled task) → writes to DynamoDB

Local dev uses [DynamoDB Local](https://hub.docker.com/r/amazon/dynamodb-local) via `docker-compose.yml`. The API also supports an in-memory fallback (`STORE_BACKEND=memory`) that fetches on startup with no external deps.

## Sources

| Category | Source | Notes |
| --- | --- | --- |
| local | 11Alive (WXIA), WSB-TV, FOX 5 Atlanta | Direct RSS |
| local | Atlanta Journal-Constitution | AJC has no public RSS; sourced via Google News query |
| state | Georgia Public Broadcasting | Direct RSS |
| state | Georgia Politics (Google News) | Aggregated query |
| national | NYT Politics, Washington Post Politics, Politico, NPR Politics | Direct RSS |
| national | AP Politics | `feeds.apnews.com` is unreliable; sourced via Google News query |

## API

| Method | Path | Description |
| --- | --- | --- |
| GET | `/healthz` | Liveness probe |
| GET | `/readyz` | Readiness — 503 until the store has data |
| GET | `/api/sources` | List configured sources |
| GET | `/api/feed` | Unified timeline, newest first. Optional `category=local\|state\|national`, `limit=1..500` (default 100) |

## Configuration

The backend reads `ATL_*` env vars (see `backend/app/config.py`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `ATL_STORE_BACKEND` | `memory` | `memory` or `dynamodb` |
| `ATL_DYNAMODB_TABLE` | `atl-news-articles` | DynamoDB table name |
| `ATL_DYNAMODB_ENDPOINT_URL` | (unset) | Override for DynamoDB Local |
| `ATL_AWS_REGION` | `us-east-1` | AWS region for DynamoDB |
| `ATL_MEMORY_REFRESH_INTERVAL_SECONDS` | `600` | Background refresh cadence in `memory` mode |

## Run locally

### Option 1: in-memory (no Docker)

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --reload --port 8000
```

The API fetches once at startup and refreshes every 10 minutes.

### Option 2: docker-compose (DynamoDB Local + fetcher + API)

```bash
docker compose up -d
curl http://127.0.0.1:8000/readyz
curl 'http://127.0.0.1:8000/api/feed?limit=5'
```

Compose runs the fetcher as a one-shot, then starts the API. To re-fetch, run `docker compose run --rm fetcher`.

### Frontend

```bash
cd frontend
cp .env.example .env.local      # default points at http://127.0.0.1:8000
npm install
npm run dev
```

## Why ECS, not EKS

For this app — a single read-only HTTP service plus one cron job — EKS adds a $73/mo control-plane fee and operational overhead the workload doesn't justify. ECS Fargate gives the same isolation, scheduling, and rolling-deploy story for a fraction of the cost.

EKS becomes the better choice when you need: a service mesh, multiple teams sharing a cluster, custom CRDs, GPU/Inferentia scheduling, or sustained CPU usage that justifies reserved EC2 nodes. Parallel EKS manifests live under `k8s/` to demonstrate the equivalent topology — they are not deployed by default.

## Roadmap

- Terraform under `infra/terraform/` (network, ECR, DynamoDB, ECS cluster + services, ALB, CloudFront, S3, EventBridge Scheduler)
- GitHub Actions: OIDC-based deploys, build → ECR → terraform apply → CloudFront invalidation
- EKS manifests under `k8s/` (Deployment, CronJob, Service, Ingress, HPA, PDB, ServiceAccount with Pod Identity)
- CloudWatch dashboard + alarms (fetcher staleness, API 5xx, DDB throttles)
