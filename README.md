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
