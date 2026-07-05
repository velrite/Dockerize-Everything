# Dockerize-Everything

A production-oriented multi-service containerized platform built 
around a single architectural principle:

> Contain the blast radius.

The goal of this project is not simply to run containers. It is to 
simulate the operational, security, and reliability patterns used 
in modern production environments.

---

## Architecture Overview

### Services

| Service | Purpose | Port |
|---------|---------|------|
| Flask API | Python web API served by Gunicorn | 8000 |
| Node API | Express.js API with database connectivity | 3000 |
| PostgreSQL | Primary persistent database | 5432 |
| Redis | Cache layer and Celery broker | 6379 |
| Apache Superset | Analytics and visualization platform | 8088 |
| Celery Worker | Background job processing | — |

---

## Network Design

Two isolated Docker networks separate application traffic from 
infrastructure services.

**Frontend Network**
Flask API · Node API

**Backend Network**
PostgreSQL · Redis · Celery Worker

Flask and Node participate in both networks and act as controlled 
entry points into backend services. This design reduces lateral 
movement opportunities and limits exposure of internal 
infrastructure components.

---

## Resource Governance

Every service operates with defined CPU and memory constraints.

| Service | CPU | Memory |
|---------|-----|--------|
| PostgreSQL | 1 CPU | 512MB |
| Flask API | 0.5 CPU | 256MB |
| Node API | 0.5 CPU | 256MB |
| Apache Superset | 1 CPU | 1GB |

Resource isolation prevents noisy-neighbor behavior where one 
service consumes resources required by others.

---

## Container Security

**Non-Root Execution**
Flask runs as appuser. Node runs as node.
Neither process has root access inside or outside the container.
Privilege escalation surface is eliminated by default.

**Multi-Stage Builds**
Both application images use multi-stage Docker builds.
No build tools ship in final images. Flask final image: 186MB.
Smaller images. Reduced attack surface. Faster distribution.

---

## Health Management

Health checks implemented for every service:
PostgreSQL · Redis · Flask API · Node API · Apache Superset · Celery Worker

Service startup is gated by dependency health rather than 
arbitrary delays. This reduces startup race conditions and 
dependency-related failures.

---

## Persistent Storage

Named Docker volumes for stateful services:
- postgres_data
- redis_data

Data survives container restarts and image rebuilds.
Container lifecycle is independent from data lifecycle.

---

## Developer Experience

**Development and Production Parity**

Environment-specific behavior layered through:
- docker-compose.yml — base production configuration
- docker-compose.override.yml — development overrides

Development mode provides hot reload, debugging support, 
and published ports — without duplicating service definitions.

**Secret Management**

All secrets injected at runtime via environment variables.
.env is gitignored. .env.example documents every required variable.
No credentials committed to version control.

---

## CI/CD Pipeline

Every push to main triggers GitHub Actions:

1. Checkout source code
2. Authenticate to GitHub Container Registry (GHCR)
3. Build Flask API image
4. Tag image with exact Git commit SHA
5. Push image to GHCR
6. Run Trivy vulnerability scan — CRITICAL and HIGH CVEs
7. Upload findings to GitHub Security tab
8. Auto-open Pull Request updating image tag in compose file

Every deployment is a reviewed, traceable PR.
Every image is scanned before it ships.
Every tag maps to an exact commit.

---

## Security Controls

| Control | Implementation |
|---------|---------------|
| Network isolation | Frontend/backend segmentation |
| Least privilege | Non-root containers |
| Resource governance | CPU and memory limits on all services |
| Vulnerability scanning | Trivy on every build |
| Secret handling | Runtime environment injection |
| Image traceability | Git SHA tagging |
| Dependency validation | Health checks before startup |

---

## Failure Testing

Failure tests were executed against the live, fully running stack using an
automated bash script that triggers a failure, polls container health status
via `docker inspect` until recovery (or timeout), and captures dependent
service logs during the outage window. Results below are directly from that
run — not simulated or assumed.

### Test 1: Flask API Hard Kill

**Command:** `docker kill flask-api`

**Result:** Flask did **not** restart automatically. The container exited
with code `137` (SIGKILL) and remained stopped until manually restarted.

**Root cause:** Docker's `restart: unless-stopped` policy recovers from
*unexpected* failures — crashes, out-of-memory kills, host reboots — but
intentionally does not override a deliberate `docker kill` or `docker stop`.
Docker treats a manual kill as an explicit instruction to stop the
container, not a fault to recover from. This is expected Docker behavior,
not a misconfiguration.

**Dependent service impact:** Node API showed no errors and continued
running normally, as it has no runtime dependency on Flask.

**Recovery:** Manual — `docker start flask-api`.

### Test 2: PostgreSQL Restart

**Command:** `docker restart postgres`

**Result:** Postgres returned to a `healthy` state in **6 seconds**.

**Dependent service impact:** Flask and Node both continued responding to
health checks throughout the restart window with no errors logged. Neither
service crashed or required manual intervention.

### Test 3: Redis Restart

**Command:** `docker restart redis`

**Result:** Redis returned to a `healthy` state in **10 seconds**.

**Dependent service impact:** The Celery worker (`superset-worker`) logged a
`Connection refused` error immediately after the restart, then automatically
reconnected within approximately 2 seconds once Redis was back, using its
built-in retry/backoff logic. No manual intervention was required and no
tasks were lost.

### Summary

| Service | Failure Type | Auto-Recovered? | Recovery Time | Notes |
|---|---|---|---|---|
| Flask API | Hard kill (SIGKILL) | ❌ No | Manual restart required | `unless-stopped` does not override a deliberate stop/kill |
| PostgreSQL | Restart | ✅ Yes | 6s | Dependents tolerated the outage with no errors |
| Redis | Restart | ✅ Yes | 10s | Celery auto-reconnected after a brief connection error |

**Key takeaway:** `restart: unless-stopped` reliably recovers services from
unexpected process failures (Postgres, Redis) but does not apply to
deliberate termination signals such as `docker kill`. This is a meaningful
distinction for reasoning about production resilience — a genuine crash and
an intentional stop are handled differently by design, and relying on a
restart policy alone is not sufficient to guarantee recovery from every kind
of failure.

**Not yet tested:** Node API termination and container rebuild with
persistent volumes reattached. Planned as a follow-up test pass.

---

## Failure Isolation Strategy

**Network Isolation** — restricts direct access to backend services
**Resource Limits** — prevents containers exhausting shared host resources
**Health Checks** — reduce dependency startup failures
**Persistent Volumes** — protect data from container lifecycle events
**Non-Root Containers** — reduce privilege exposure on compromise

---

## Running Locally

```bash
# Clone the repository
git clone https://github.com/velrite/Dockerize-Everything.git
cd Dockerize-Everything

# Copy environment variables
cp .env.example .env

# Start in development mode
docker compose up

# Start in production mode
docker compose -f docker-compose.yml up
```

---

## Key Takeaway

The hardest part of containerization is not building containers.

It is designing systems that remain observable, secure, recoverable, 
and predictable when components fail.

This project explores those engineering trade-offs through a 
production-oriented multi-service platform built around 
explicit failure isolation at every layer.

---

## Author

Olamide Olalekan — Platform & DevSecOps Engineer
[LinkedIn](https://linkedin.com/in/olamide-olalekan-12138a265) | 
[GitHub](https://github.com/velrite)

## Related Projects

- [Auto-healing Kubernetes Platform](https://github.com/velrite/auto-healing-k8s--)
- [Terraform Kubernetes Platform](https://github.com/velrite/Terraform-Kubernetes-Platform)
