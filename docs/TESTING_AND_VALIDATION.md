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
