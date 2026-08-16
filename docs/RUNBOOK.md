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
