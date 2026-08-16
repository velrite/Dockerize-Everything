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
