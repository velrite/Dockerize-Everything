FROM apache/superset:3.1.3
 
USER root
 
RUN pip install --no-cache-dir \
    psycopg2-binary==2.9.9 \
    redis==4.6.0
 
COPY superset_config.py /app/pythonpath/superset_config.py
 
USER superset
 
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8088/health || exit 1





