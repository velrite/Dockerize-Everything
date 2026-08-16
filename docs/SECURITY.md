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
