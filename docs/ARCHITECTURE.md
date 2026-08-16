# Architecture

## Network Design

Two isolated Docker networks separate application traffic from infrastructure services.

```
┌─────────────────────────────────────────────┐
│              FRONTEND NETWORK               │
│   flask-api        node-api                 │
│       │                │                   │
│       └────────┬───────┘                   │
└────────────────│────────────────────────────┘
                 │
┌────────────────│────────────────────────────┐
│              BACKEND NETWORK                │
│       │                │                   │
│   postgres          redis                  │
│                  superset-worker           │
└─────────────────────────────────────────────┘
```

Flask and Node participate in both networks. They are the only controlled entry points into backend services. Postgres and Redis are unreachable without going through the API layer first. This limits lateral movement if any frontend service is compromised.

Superset sits on both networks because it needs to read from Postgres directly and use Redis as its broker.

---

## Service Startup Order

```
postgres (healthcheck: pg_isready)
    └── flask-api (depends_on: postgres healthy)
    └── node-api (depends_on: postgres healthy)
    └── superset (depends_on: postgres healthy, redis healthy)
    └── superset-worker (depends_on: postgres healthy, redis healthy)

redis (healthcheck: redis-cli ping)
    └── superset
    └── superset-worker
```

`depends_on: condition: service_healthy` is used throughout. Without this, Docker only waits for the container process to start — not for the service inside to be ready. Postgres takes several seconds to accept connections after the process starts.

---

## Storage

| Volume | Service | Purpose |
|--------|---------|---------|
| postgres_data | PostgreSQL | Database files |
| redis_data | Redis | Append-only persistence log |

Named volumes are used throughout. Anonymous volumes (no name prefix) get random IDs and cannot be reliably reattached after container removal. Named volumes persist independently of container lifecycle.

---

## Resource Limits

| Service | CPU Limit | Memory Limit | Memory Reservation |
|---------|-----------|--------------|-------------------|
| PostgreSQL | 1.0 | 512MB | 256MB |
| Redis | 0.5 | 256MB | — |
| Flask API | 0.5 | 256MB | — |
| Node API | 0.5 | 256MB | — |
| Superset | 1.0 | 1GB | — |
| Superset Worker | 1.0 | 768MB | — |

Without resource limits, one runaway container can exhaust all CPU or memory on the host and cascade failures across every other service.

---

## Image Sizes

| Image | Size |
|-------|------|
| flask-api | 186MB |
| node-api | 297MB |
| superset | 1.89GB |

Flask and Node use multi-stage builds. Build tools are used in a builder stage and not shipped in the final image. The Superset image is large because it is based on the official Apache Superset image which includes a full Python data science environment.

---

## Dev vs Production

| Concern | Development | Production |
|---------|-------------|------------|
| Flask server | Flask dev server with --debug | Gunicorn (4 workers) |
| Node server | nodemon (hot reload) | node src/index.js |
| Ports | 8000 and 3000 published | Internal only |
| Code mount | ./flask-app/app mounted live | Baked into image |
| Config source | docker-compose.override.yml (auto-merged) | docker-compose.yml only |
