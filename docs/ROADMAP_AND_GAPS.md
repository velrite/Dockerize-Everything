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
