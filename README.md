# atl-news

Unified RSS news feed covering Atlanta local news, Georgia state politics, and US national politics. Backend service that polls a curated set of RSS feeds, normalizes them into a single schema, and exposes a JSON API.

This first iteration is the **backend only**. A React frontend and EKS manifests will follow.

## Sources

| Category | Source | Notes |
| --- | --- | --- |
| local | 11Alive (WXIA), WSB-TV, FOX 5 Atlanta | Direct RSS |
| local | Atlanta Journal-Constitution | AJC has no public RSS; sourced via Google News query |
| state | Georgia Public Broadcasting | Direct RSS |
| state | Georgia Politics (Google News) | Aggregated query |
| national | NYT Politics, Washington Post Politics, Politico, NPR Politics | Direct RSS |
| national | AP Politics | `feeds.apnews.com` is unreliable; sourced via Google News query |

All URLs were verified live before being added to `backend/app/sources.py`.

## API

| Method | Path | Description |
| --- | --- | --- |
| GET | `/healthz` | Liveness probe |
| GET | `/api/sources` | List configured sources |
| GET | `/api/feed` | Unified timeline, newest first. Optional `category=local\|state\|national`, `limit=1..500` (default 100) |
| POST | `/api/refresh` | Force a cache refresh |

Articles are cached in-memory for 5 minutes and deduplicated by URL across sources.

## Run locally

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Then:

```bash
curl http://127.0.0.1:8000/healthz
curl 'http://127.0.0.1:8000/api/feed?limit=5'
curl 'http://127.0.0.1:8000/api/feed?category=local&limit=10'
```

## Run in Docker

```bash
cd backend
docker build -t atl-news-backend .
docker run --rm -p 8000:8000 atl-news-backend
```

## Roadmap

- React frontend (Vite + TS) consuming `/api/feed`
- `docker-compose.yml` for local dev
- EKS manifests under `k8s/` (Deployment + Service + Ingress via AWS Load Balancer Controller)
- ECR push + GitHub Actions CI
