# ── Stage 1: dependency builder ─────────────────────────────────────────
# We use a named build stage. This is multi-stage build pattern.
# alpine is 5 MB vs ubuntu's 75 MB. We want small.
FROM python:3.12-slim AS builder
 
# Set the working directory in the builder stage
WORKDIR /build
 
# Copy ONLY requirements first.
# WHY: Docker caches layers. If you copy everything first and then install
# deps, any code change busts the cache and reinstalls everything.
# Copy requirements FIRST → install → THEN copy code.
# This is the single most important build-time optimization.
COPY requirements.txt .
 
# Install deps into a prefix so we can copy just the deps to the final stage
# --no-cache-dir     → don't store pip's cache inside the image
# --prefix=/install  → install to a custom path we'll copy later
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
 
# ── Stage 2: final runtime image ────────────────────────────────────────
FROM python:3.12-slim AS final
 
# Security: Create a non-root user and group
# We will NEVER run as root in production. Never.
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser
 
WORKDIR /app
 
# Copy ONLY the installed packages from the builder stage
# The builder's /build directory and pip cache stay behind — not in this image
COPY --from=builder /install /usr/local
 
# Now copy application code
COPY app/ ./app/
 
# Switch to non-root user BEFORE exposing or running anything
USER appuser
 
# Document the port — this is metadata, it does NOT publish the port
EXPOSE 8000
 
# Health check: Docker daemon will probe this every 30s
# If it fails 3 times, the container is marked unhealthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
 
# Use exec form (JSON array), not shell form.
# Shell form wraps in /bin/sh -c which means signals don't reach your app.
# Exec form means Docker sends SIGTERM directly to gunicorn → graceful shutdown.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:create_app()"]
