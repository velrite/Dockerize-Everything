#!/bin/bash
set -e

echo "Creating documentation structure..."
mkdir -p docs

# ─── README.md ───────────────────────────────────────────────────────────────
cat > README.md << 'EOF'
# Dockerize-Everything

A production-oriented multi-service containerized platform built around a single architectural principle:

> Contain the blast radius.

The goal of this project is not simply to run containers. It is to simulate the operational, security, and reliability patterns used in modern production environments.

---

## Quick Start

```bash
git clone https://github.com/velrite/Dockerize-Everything.git
cd Dockerize-Everything
cp .env.example .env
# Fill in your values in .env
docker compose up -d
```

---

## Services

| Service | Purpose | Port |
|---------|---------|------|
| Flask API | Python web API served by Gunicorn | 8000 (internal) |
| Node API | Express.js API with database connectivity | 3000 (internal) |
| PostgreSQL | Primary persistent database | 5432 (internal) |
| Redis | Cache layer and Celery broker | 6379 (internal) |
| Apache Superset | Analytics and visualization platform | 8088 |
| Celery Worker | Background job processing | — |

Flask and Node APIs are not exposed to the host by default. Only Superset exposes port 8088. In production, an Nginx or Traefik reverse proxy would sit in front of all services.

---

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — network design, service layout, storage
- [Architecture Decision Records](docs/ADR.md) — every major decision and the road not taken
- [Security](docs/SECURITY.md) — controls, threat model, what is and isn't covered
- [Runbook](docs/RUNBOOK.md) — how to operate this stack day to day
- [Testing and Validation](docs/TESTING_AND_VALIDATION.md) — real failure test results with captured output
- [Incidents](docs/INCIDENTS.md) — real issues hit during this build and how they were resolved
- [Gaps and Roadmap](docs/ROADMAP_AND_GAPS.md) — what is not built and what building it properly would require
- [Simplicity vs Production Trade-offs](docs/SIMPLICITY_VS_PRODUCTION_TRADEOFFS.md) — honest assessment of every over-engineered choice

---

## CI/CD

Every push to main triggers GitHub Actions:
1. Build Flask API image
2. Push to GitHub Container Registry tagged with Git commit SHA
3. Trivy vulnerability scan — findings uploaded to GitHub Security tab
4. Auto-open Pull Request updating image tag in compose file

---

## Author

Olamide Olalekan — Platform and DevSecOps Engineer
[LinkedIn](https://linkedin.com/in/olamide-olalekan-12138a265) | [GitHub](https://github.com/velrite)
EOF

echo "✓ README.md"

# ─── ARCHITECTURE.md ─────────────────────────────────────────────────────────
cat > docs/ARCHITECTURE.md << 'EOF'
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
EOF

echo "✓ docs/ARCHITECTURE.md"

# ─── ADR.md ──────────────────────────────────────────────────────────────────
cat > docs/ADR.md << 'EOF'
# Architecture Decision Records

Every major decision, the road not taken, and why.

---

## ADR-001: Multi-Stage Docker Builds

**Context:** Python and Node apps require build tools (gcc, npm) to compile dependencies. These tools are not needed at runtime.

**Decision:** Use multi-stage builds. Compile in a builder stage. Copy only compiled output into a minimal final stage.

**Alternatives Rejected:**
- Single stage build — simpler Dockerfile but ships ~1.5GB of build tools into production. More attack surface, slower pulls.
- Pre-built wheels only — requires maintaining a separate wheel cache. More operational overhead for marginal gain.

**Trade-off Accepted:** Slightly more complex Dockerfile. Worth it for 186MB vs ~1.5GB final image.

**What Would Revisit This:** Distroless base images would reduce the final image further but require more careful dependency management. Planned as a future improvement.

---

## ADR-002: Frontend / Backend Network Segmentation

**Context:** All services need to communicate but not all services should be reachable from the same network.

**Decision:** Two networks. Frontend for externally-accessible services. Backend for databases and internal workers. Flask and Node bridge both.

**Alternatives Rejected:**
- Single network for all services — simpler but Postgres and Redis become reachable from any compromised service.
- Three networks (DMZ pattern) — adds operational complexity without meaningful additional isolation at this scale.

**Trade-off Accepted:** Slightly more complex compose file. Worth it for meaningful network isolation.

**What Would Revisit This:** In Kubernetes this becomes NetworkPolicy objects which are more expressive. The Compose network approach is a stepping stone.

---

## ADR-003: Non-Root Container Users

**Context:** Containers running as root are UID 0 on the host kernel if container isolation breaks.

**Decision:** Flask runs as appuser. Node runs as the built-in node user. Both created before application code is copied.

**Alternatives Rejected:**
- Root containers — simpler but eliminates a meaningful security layer.
- USER nobody — technically more restrictive but breaks some filesystem operations without careful permission management.

**Trade-off Accepted:** Slightly more complex Dockerfile setup. Non-negotiable for any production-adjacent workload.

**What Would Revisit This:** Rootless Docker at the daemon level would add another layer. Not implemented here.

---

## ADR-004: Runtime Secret Injection via .env

**Context:** Secrets must not be hardcoded in code or Dockerfiles. Image layers are permanent — a secret baked into a RUN command lives in that layer forever.

**Decision:** All secrets injected at runtime via environment variables from a .env file. .env is gitignored. .env.example documents required variables without values.

**Alternatives Rejected:**
- Docker Secrets (Swarm) — more secure (mounted as files, not visible in docker inspect) but requires Docker Swarm mode.
- HashiCorp Vault dynamic credentials — the production-correct answer but significant operational overhead for a single-host setup.
- Hardcoded values — never acceptable.

**Trade-off Accepted:** Environment variables are visible to all processes in the container and can leak through logs. Acceptable for dev and staging. Production workloads should use Docker Secrets or Vault.

**What Would Revisit This:** Moving to Vault for dynamic credential rotation is the planned next step for a production deployment of this stack.

---

## ADR-005: Git SHA Image Tagging

**Context:** Docker images need a stable, traceable identifier.

**Decision:** Every image pushed to GHCR is tagged with the exact Git commit SHA.

**Alternatives Rejected:**
- latest tag — not a version. Changes on every build. Cannot determine what is running in production.
- Semantic versioning — requires manual version management. SHA is automatic and always unique.
- Date-based tags — human-readable but not directly tied to code.

**Trade-off Accepted:** SHA tags are not human-readable. Worth it for exact traceability from running container back to source commit.

**What Would Revisit This:** Adding semantic version tags in addition to SHA for human-readable release tracking.

---

## ADR-006: Trivy Scan with exit-code 0 (Report Only)

**Context:** Trivy found CVEs in the Flask base image (python:3.12-slim). Setting exit-code: 1 fails the pipeline on every build.

**Decision:** Set exit-code: 0. Pipeline continues. Findings are uploaded to GitHub Security tab for review.

**Alternatives Rejected:**
- exit-code: 1 — pipeline fails on every build because the base image has known CVEs that are not yet fixed upstream. No productive signal.
- Skip scanning — loses visibility entirely.
- Pin to a specific digest — reduces CVE noise but requires manual updates when fixes land.

**Trade-off Accepted:** Pipeline does not enforce CVE-free images. This is intentional for a portfolio project using public base images with known but low-severity findings. In production, CRITICAL CVEs would block deployment.

**What Would Revisit This:** Adding severity filtering so only CRITICAL findings block the pipeline while HIGH findings are reported.
EOF

echo "✓ docs/ADR.md"

# ─── SECURITY.md ─────────────────────────────────────────────────────────────
cat > docs/SECURITY.md << 'EOF'
# Security

## Controls Implemented

| Control | Implementation | Status |
|---------|---------------|--------|
| Non-root execution | appuser (Flask), node (Node) | ✅ Implemented |
| Network segmentation | Frontend/backend Docker networks | ✅ Implemented |
| Resource limits | CPU and memory caps on all services | ✅ Implemented |
| Secret injection | Runtime .env, gitignored | ✅ Implemented |
| Vulnerability scanning | Trivy on every CI build | ✅ Implemented |
| Image traceability | Git SHA tagging to GHCR | ✅ Implemented |
| Health-gated startup | depends_on: condition: service_healthy | ✅ Implemented |
| No published DB ports | Postgres and Redis internal only | ✅ Implemented |

---

## Controls Not Implemented

**Read-only root filesystem**
Adding `read_only: true` to service definitions prevents runtime modification of application code. Not implemented. Would require tmpfs mounts for log and temp directories. Planned improvement.

**Docker Content Trust / Image Signing**
Images are not signed. Pulling from GHCR does not verify image provenance beyond the SHA tag. Cosign or Notary would address this.

**Secrets Management (Vault)**
Secrets are environment variables. Visible to all processes in the container. Acceptable for dev and staging. Production should use HashiCorp Vault dynamic credentials or Docker Secrets.

**TLS Between Services**
Inter-service communication is unencrypted inside Docker networks. This is acceptable within a single trusted host. In a multi-host environment, mTLS (via SPIFFE/SPIRE or a service mesh) would be required.

**Pod Security Standards / Admission Control**
Not applicable to Docker Compose. In Kubernetes this would be addressed with Kyverno or OPA policies.

---

## Threat Model

**What this stack protects against:**
- A compromised frontend service reaching the database directly (network segmentation)
- Privilege escalation from container to host via root (non-root users)
- One service consuming all host resources (resource limits)
- Secrets appearing in Git history (gitignored .env)
- Known CVEs shipping undetected (Trivy scanning)

**What this stack does not protect against:**
- A compromised host machine
- Secrets leaking through container logs if an application logs env vars
- Supply chain attacks on base images (mitigated partially by Trivy)
- Lateral movement within the same Docker network

---

## Verification Commands

```bash
# Confirm non-root execution
docker compose exec flask-api whoami
# Expected: appuser

docker compose exec node-api whoami
# Expected: node

# Confirm no secrets in environment beyond what is expected
docker compose exec flask-api env | sort

# Confirm Postgres is not reachable from frontend-only services
# (No direct test implemented — enforced by network config)
```
EOF

echo "✓ docs/SECURITY.md"

# ─── RUNBOOK.md ──────────────────────────────────────────────────────────────
cat > docs/RUNBOOK.md << 'EOF'
# Runbook

Day-to-day operational procedures for this stack.

---

## Starting the Stack

```bash
# Development (auto-merges override file)
docker compose up -d

# Production (explicitly ignores override)
docker compose -f docker-compose.yml up -d

# Check status
docker compose ps
```

All services should reach healthy status within 60 seconds. Postgres and Redis start first. Flask, Node, and Superset wait for their dependencies to pass healthchecks.

---

## Verifying Health

```bash
# Check all service statuses
docker compose ps

# Test Flask API
curl http://localhost:8000/health
# Expected: {"status": "ok", "service": "flask-api"}

# Test Node API
curl http://localhost:3000/health
# Expected: {"status": "ok", "service": "node-api"}

# Test Node DB connectivity
curl http://localhost:3000/db-health
# Expected: {"status": "ok", "db_time": "..."}

# Open Superset
# http://localhost:8088
# Login: admin / (your SUPERSET_ADMIN_PASSWORD)
```

Note: Flask and Node health endpoints are only reachable on localhost when running in development mode with the override file. In production mode, exec into the container or use docker inspect to check health.

---

## Debugging

```bash
# View logs for a specific service
docker compose logs flask-api
docker compose logs node-api --follow

# Check environment variables actually set in a container
docker compose exec node-api env | sort

# Inspect container health check output
docker inspect --format='{{json .State.Health}}' dockerize-everything-postgres-1 | python3 -m json.tool

# Check resource usage in real time
docker stats

# Exec into a container
docker compose exec flask-api /bin/sh
```

---

## Stopping the Stack

```bash
# Stop without removing volumes (data preserved)
docker compose down

# Stop and remove all volumes (data destroyed — use with caution)
docker compose down -v
```

---

## Rebuilding After Code Changes

```bash
# Rebuild a specific service
docker compose up -d --build flask-api

# Rebuild all
docker compose build
docker compose up -d
```

---

## Superset Initialization (First Time Only)

```bash
docker exec dockerize-everything-superset-1 superset db upgrade
docker exec dockerize-everything-superset-1 superset init
docker exec -it dockerize-everything-superset-1 superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@example.com \
  --password yourpassword
```

---

## Common Issues

**Postgres fails to start: password authentication failed**
The postgres_data volume was initialized with different credentials. Run `docker compose down -v` to wipe volumes and reinitialize with current .env values.

**node-api crash loop: SyntaxError**
Application code has a syntax error. Check `docker logs dockerize-everything-node-api-1`. Fix the code and rebuild: `docker compose up -d --build node-api`.

**Services not picking up .env changes**
`docker compose restart` does not reload env vars. Run `docker compose down && docker compose up -d`.

**Superset 500 error on login**
SUPERSET_SECRET_KEY is blank or missing in .env. Generate one: `python3 -c "import secrets; print(secrets.token_hex(32))"` and set it in .env. Then restart the stack.
EOF

echo "✓ docs/RUNBOOK.md"

# ─── TESTING_AND_VALIDATION.md ───────────────────────────────────────────────
cat > docs/TESTING_AND_VALIDATION.md << 'EOF'
# Testing and Validation

All results below are from actual test runs against the live stack. Nothing is simulated or assumed.

---

## Service Health Verification

```bash
$ curl http://localhost:8000/health
{"service": "flask-api", "status": "ok"}

$ curl http://localhost:3000/health
{"status":"ok","service":"node-api"}

$ curl http://localhost:3000/db-health
{"status":"ok","db_time":"2026-06-04T18:18:41.856Z"}
```

All three endpoints confirmed live during the build session.

---

## Non-Root Verification

```bash
$ docker compose exec flask-api whoami
appuser
```

Confirmed. Flask does not run as root.

---

## Failure Tests

Tests were executed against the fully running stack. An automated bash script triggered each failure, polled container health via `docker inspect` until recovery or timeout, and captured dependent service logs during the outage window.

### Test 1: Flask API Hard Kill

**Command:** `docker kill flask-api`

**Result:** Flask did not restart automatically. The container exited with code 137 (SIGKILL) and remained stopped until manually restarted.

**Root cause:** `restart: unless-stopped` recovers from unexpected failures — crashes, OOM kills, host reboots — but does not override a deliberate `docker kill` or `docker stop`. Docker treats a manual kill as an explicit instruction, not a fault. This is correct Docker behavior, not a misconfiguration.

**Dependent service impact:** Node API showed no errors and continued running normally. It has no runtime dependency on Flask.

**Recovery:** Manual — `docker start flask-api`.

---

### Test 2: PostgreSQL Restart

**Command:** `docker restart postgres`

**Result:** Postgres returned to healthy in 6 seconds.

**Dependent service impact:** Flask and Node both continued responding to health checks throughout the restart window. Neither crashed or required intervention. The depends_on healthcheck gate applies only at startup — it does not kill dependents if Postgres restarts later. Both services have connection pooling configured (Flask via SQLAlchemy, Node via pg Pool) which handled the brief outage transparently.

---

### Test 3: Redis Restart

**Command:** `docker restart redis`

**Result:** Redis returned to healthy in 10 seconds.

**Dependent service impact:** The Celery worker logged a `Connection refused` error immediately after the restart, then automatically reconnected within approximately 2 seconds once Redis was back. Built-in retry/backoff logic handled recovery. No tasks were lost. No manual intervention required.

---

### Summary

| Service | Failure Type | Auto-Recovered | Recovery Time | Notes |
|---------|-------------|----------------|---------------|-------|
| Flask API | Hard kill (SIGKILL) | No | Manual restart required | unless-stopped does not override deliberate stop |
| PostgreSQL | Restart | Yes | 6s | Dependents tolerated outage without errors |
| Redis | Restart | Yes | 10s | Celery auto-reconnected after brief connection error |

**Key distinction:** `restart: unless-stopped` reliably recovers from unexpected process failures but does not apply to deliberate termination signals. A genuine crash and an intentional stop are handled differently by design. Relying on a restart policy alone is not sufficient to guarantee recovery from every kind of failure.

---

## Not Yet Tested

- Node API termination and recovery behavior
- Container rebuild with persistent volumes reattached
- Superset behavior during Postgres extended outage (beyond a restart)
- Resource limit enforcement under synthetic load

These are planned as a follow-up test pass.
EOF

echo "✓ docs/TESTING_AND_VALIDATION.md"

# ─── INCIDENTS.md ────────────────────────────────────────────────────────────
cat > docs/INCIDENTS.md << 'EOF'
# Incidents

Real issues encountered during the build of this project. Every entry is a genuine failure with a real root cause and fix — nothing hypothetical.

---

## INC-001: docker-compose.override.yml Service Name Mismatch

**What Happened:**
`make build` failed with `service "flask-app" has neither an image nor a build context specified`.

**Root Cause:**
The override file used service names `flask-app` and `node-app`. The main compose file defined them as `flask-api` and `node-api`. Docker Compose merged both files but the override referenced services that didn't exist in the main file, creating dangling service definitions with no build context.

**Fix:**
Updated docker-compose.override.yml to use `flask-api` and `node-api` to match the main compose file.

**Prevention:**
Override files must use identical service names to the base compose file. Any rename in docker-compose.yml must be reflected in the override file.

---

## INC-002: node-api Crash Loop — package-lock.json Out of Sync

**What Happened:**
`make build` failed during node-api image build with `npm error: npm ci can only install packages when your package.json and package-lock.json are in sync`.

**Root Cause:**
package.json listed dependencies (express, pg, nodemon) that were not present in package-lock.json. The lock file was either missing or generated from a different package.json state.

**Fix:**
Ran `npm install` locally inside node-app/ to regenerate the lock file in sync with package.json. Then rebuilt.

**Prevention:**
Always commit package-lock.json alongside package.json. Run `npm install` locally before committing dependency changes.

---

## INC-003: node-api Crash Loop — SyntaxError: Unexpected End of Input

**What Happened:**
node-api container entered a crash loop immediately after startup. Logs showed `SyntaxError: Unexpected end of Input` at line 48 of index.js.

**Root Cause:**
The `app.listen()` callback was missing its closing `});`. The file ended mid-function.

**Fix:**
```bash
echo "});" >> node-app/src/index.js
docker compose up -d --build node-api
```

**Prevention:**
Syntax validation before commit. A pre-commit hook running `node --check src/index.js` would catch this before it reaches the container.

---

## INC-004: Postgres Repeated Authentication Failures

**What Happened:**
Postgres container repeatedly failed to start with `password authentication failed`. Persisted across multiple `docker compose down -v` cycles.

**Root Cause:**
Multiple compounding typos in .env:
- `POSTGRES_USER=postgress` (double s) — Postgres initialized with user `postgress` but connection attempts used `postgres`
- `NODE_DB_USER=appuser` — Node tried to connect as a user that was never created
- `NODE_DB_NAME=yourdbname` — Literal placeholder value, not the actual DB name
- `DATABASE_URL=postgresql+psycopg2://appuser:CHANGE_ME@postgres:5432/appdb` — Superset connecting as a non-existent user with a placeholder password

**Fix:**
Corrected all values in .env:
```
POSTGRES_USER=postgres
NODE_DB_USER=postgres
NODE_DB_NAME=appdb
DATABASE_URL=postgresql+psycopg2://postgres:yourpassword@postgres:5432/appdb
```
Then ran `docker compose down -v && docker compose up -d` to wipe the volume and reinitialize Postgres with the correct credentials.

**Prevention:**
The .env.example file should document exact expected formats, not just variable names. A startup validation script that checks DB connectivity before marking the stack healthy would surface this immediately.

---

## INC-005: Superset redis Package Version Conflict

**What Happened:**
`superset db upgrade` failed with `ContextualVersionConflict: redis 5.0.1, Requirement redis<5.0,>=4.5.4`.

**Root Cause:**
The custom Superset Dockerfile installed `redis==5.0.1` as an additional dependency. Apache Superset 3.1.3 requires `redis<5.0`. The newer version broke Superset's internal package resolution.

**Fix:**
Changed Dockerfile to install `redis==4.6.0` instead. Rebuilt the image.

**Prevention:**
When extending official images with additional pip packages, always verify version compatibility against the base image's existing dependency constraints before pinning a version.

---

## INC-006: Superset 500 Error on Login — Missing Secret Key

**What Happened:**
Superset loaded but returned HTTP 500 on the login page. Logs showed `RuntimeError: The session is unavailable because no secret key was set`.

**Root Cause:**
`SUPERSET_SECRET_KEY` was blank in .env. The superset_config.py reads this with `os.environ['SUPERSET_SECRET_KEY']` which returns an empty string rather than raising an error. Flask silently accepted the empty key but failed when trying to use it for session signing.

**Fix:**
Generated a proper secret key and set it in .env:
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

**Prevention:**
superset_config.py should validate that SECRET_KEY is non-empty at startup and raise a clear error rather than accepting an empty value silently.

---

## INC-007: GitHub Actions Workflow YAML Indentation Error

**What Happened:**
GitHub Actions rejected the workflow file with `Unexpected value 'open-pr'` at line 59.

**Root Cause:**
The `open-pr` job was written at column 0 instead of indented under the `jobs:` key. It appeared as a top-level YAML key rather than a job definition.

**Fix:**
Rewrote the workflow file with correct indentation. `open-pr:` indented two spaces under `jobs:`.

**Prevention:**
Validate workflow YAML locally with `actionlint` before pushing. GitHub's workflow editor also shows syntax errors before saving.
EOF

echo "✓ docs/INCIDENTS.md"

# ─── ROADMAP_AND_GAPS.md ─────────────────────────────────────────────────────
cat > docs/ROADMAP_AND_GAPS.md << 'EOF'
# Gaps and Roadmap

What is not built, stated plainly. What building it properly would require.

---

## Not Built

### Reverse Proxy (Nginx or Traefik)

Flask and Node APIs are not exposed through a reverse proxy. In development they are published directly to localhost ports. In production, a reverse proxy is required as the single entry point handling TLS termination, routing, and rate limiting.

**What building it properly requires:**
- An Nginx or Traefik service added to the compose file on the frontend network
- TLS certificates via Certbot (Nginx) or built-in Let's Encrypt integration (Traefik)
- Routing rules mapping paths to upstream services
- Rate limiting configuration
- Access logging

---

### Centralized Logging

Each service writes logs to stdout. Docker captures them locally. There is no aggregation, search, or alerting on log content.

**What building it properly requires:**
- Loki + Grafana stack, or ELK (Elasticsearch, Logstash, Kibana)
- A log shipper (Promtail for Loki, Filebeat for ELK) running as a sidecar or on the host
- Structured JSON logging from each application
- Log retention policy and storage sizing

---

### Metrics and Alerting

There are no Prometheus metrics, no Grafana dashboards, and no alerting rules. The stack is observable only through docker stats and docker compose logs.

**What building it properly requires:**
- Prometheus with a docker-compose service and scrape config
- cAdvisor or Docker daemon metrics for container-level resource data
- Application-level /metrics endpoints in Flask and Node (prometheus_client, prom-client)
- Grafana with dashboards for Golden Signals (latency, traffic, errors, saturation) per service
- Alertmanager with rules for SLO-impacting conditions

---

### Automated Backup

Named volumes persist data but there are no automated backups of Postgres or Redis data.

**What building it properly requires:**
- A scheduled pg_dump script (cron or a dedicated backup container)
- Backup rotation and retention policy
- Offsite storage (S3, GCS, or equivalent)
- Restore testing procedure

---

### Node API CI Build

The GitHub Actions pipeline builds and scans only the Flask API image. Node API and Superset images are not built or scanned in CI.

**What building it properly requires:**
- Additional build steps for node-api and superset in the workflow
- Separate Trivy scan steps per image
- Matrix strategy or parallel jobs to avoid sequential build time

---

### Integration Tests in CI

The pipeline builds and scans images but does not run the stack and verify endpoints respond correctly.

**What building it properly requires:**
- A test job that runs `docker compose up` in CI
- Health check polling until all services are ready
- curl assertions against /health and /db-health endpoints
- Teardown after tests complete

---

## Planned Improvements

1. Add Nginx reverse proxy with TLS
2. Extend CI pipeline to build all three application images
3. Add integration test job to CI
4. Implement read-only root filesystem on Flask and Node containers
5. Add Prometheus + Grafana for metrics visibility
6. Move to Vault for dynamic credential rotation
7. Run extended failure test pass covering Node API termination and volume reattachment
EOF

echo "✓ docs/ROADMAP_AND_GAPS.md"

# ─── SIMPLICITY_VS_PRODUCTION_TRADEOFFS.md ───────────────────────────────────
cat > docs/SIMPLICITY_VS_PRODUCTION_TRADEOFFS.md << 'EOF'
# Simplicity vs Production Trade-offs

For every choice that added complexity, here is the simpler alternative, what it would save, what it would cost, and an honest statement of whether the added complexity was worth it.

---

## Multi-Stage Docker Builds

**What was done:** Two-stage build. Compile in builder. Copy output into minimal final image.

**Simpler alternative:** Single-stage build. One FROM, install everything, run.

**What the simpler version saves:** 10-15 lines of Dockerfile. No need to understand stage copying.

**What you lose:** Build tools (gcc, pip cache, npm) ship in the production image. Flask image would be ~1.5GB instead of 186MB. Larger attack surface. Slower image pulls and pushes.

**Was the complexity worth it:** Yes. The size difference is an order of magnitude and the security argument is real. This is standard practice, not over-engineering.

---

## Two Docker Networks

**What was done:** Separate frontend and backend networks. Flask and Node bridge both. Postgres and Redis backend-only.

**Simpler alternative:** One network for all services.

**What the simpler version saves:** 6 lines in compose file. No need to understand Docker network segmentation.

**What you lose:** Postgres becomes reachable from any container on the network. If Superset is compromised, it can connect to Postgres directly without going through the API layer.

**Was the complexity worth it:** Yes for a project demonstrating production security patterns. For a personal project with no sensitive data, a single network is fine. The point of this project is to demonstrate the pattern, so the added complexity is the demonstration.

---

## Health Checks on Every Service

**What was done:** HEALTHCHECK defined in every Dockerfile. depends_on: condition: service_healthy throughout.

**Simpler alternative:** No HEALTHCHECK. No condition on depends_on. Add a sleep 10 to startup scripts.

**What the simpler version saves:** Health check definitions in each Dockerfile. Condition syntax in compose.

**What you lose:** Race conditions at startup. Flask starts before Postgres is ready. Connection errors. Manual restart required. sleep 10 is a guess — too short on slow machines, wasteful on fast ones.

**Was the complexity worth it:** Yes, unconditionally. Health checks solve a real problem. sleep is not a solution, it is a workaround. This is one of the most important patterns in this project.

---

## Resource Limits on Every Service

**What was done:** CPU and memory limits defined for all six services.

**Simpler alternative:** No resource limits.

**What the simpler version saves:** 6 lines per service in compose. No need to think about sizing.

**What you lose:** Any service can consume all available CPU or memory. One Superset query running wild can starve Postgres and cascade failures across the entire stack.

**Was the complexity worth it:** Yes. This is one of the most common causes of production outages in container environments and one of the easiest to prevent.

---

## Git SHA Image Tagging

**What was done:** Images tagged with full Git commit SHA. Pushed to GHCR.

**Simpler alternative:** Tag as latest. Push to Docker Hub.

**What the simpler version saves:** No GHCR setup. No SHA handling in workflow. latest is always the newest.

**What you lose:** No traceability. Cannot determine which commit is running in production. Rolling back means knowing which SHA to specify. latest in a compose file means the next pull changes behavior silently.

**Was the complexity worth it:** Yes. SHA tagging is the minimum standard for any serious deployment. The operational cost is minimal once the pipeline is set up.

---

## Automated PR on Image Build

**What was done:** GitHub Actions opens a PR updating the image tag after every successful build.

**Simpler alternative:** Manually update the compose file when deploying.

**What the simpler version saves:** The open-pr job in the workflow. No peter-evans/create-pull-request dependency.

**What you lose:** Every deployment becomes a manual operation. No audit trail of what was deployed when. No review gate before deployment.

**Was the complexity worth it:** For a single-developer portfolio project, the PR automation is more demonstration than operational necessity. The pattern is correct for team environments where deployments should be reviewed. For solo work it adds process without adding safety. Included here to demonstrate the pattern, not because the project strictly requires it.
EOF

echo "✓ docs/SIMPLICITY_VS_PRODUCTION_TRADEOFFS.md"

# ─── Git commit and push ──────────────────────────────────────────────────────
echo ""
echo "All documentation files created. Committing and pushing..."

git add .
git commit -m "docs: add complete project documentation

- README.md with quick start and service table
- docs/ARCHITECTURE.md with network design, startup order, storage
- docs/ADR.md with 6 architecture decision records
- docs/SECURITY.md with controls implemented and threat model
- docs/RUNBOOK.md with operational procedures
- docs/TESTING_AND_VALIDATION.md with real failure test results
- docs/INCIDENTS.md with 7 real incidents from this build
- docs/ROADMAP_AND_GAPS.md with honest gaps assessment
- docs/SIMPLICITY_VS_PRODUCTION_TRADEOFFS.md with trade-off analysis"

git push

echo ""
echo "Done. All documentation pushed to GitHub."
