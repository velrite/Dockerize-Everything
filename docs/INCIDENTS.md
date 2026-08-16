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
