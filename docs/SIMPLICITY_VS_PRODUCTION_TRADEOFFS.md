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
