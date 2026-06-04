import os
 
# ─────────────────────────────────────────────────────────────────────────
# SECURITY SETTINGS
# ─────────────────────────────────────────────────────────────────────────
 
# SECRET_KEY must be a long random string — inject via environment variable
# Generate one with: python -c "import secrets; print(secrets.token_hex(32))"
SECRET_KEY = os.environ['SUPERSET_SECRET_KEY']
 
# ─────────────────────────────────────────────────────────────────────────
# DATABASE
# ─────────────────────────────────────────────────────────────────────────
SQLALCHEMY_DATABASE_URI = os.environ['DATABASE_URL']
 
# ─────────────────────────────────────────────────────────────────────────
# CACHE (Redis)
# ─────────────────────────────────────────────────────────────────────────
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_URL': os.environ['REDIS_URL'],
}
 
# ─────────────────────────────────────────────────────────────────────────
# CELERY (async query execution)
# ─────────────────────────────────────────────────────────────────────────
class CeleryConfig:
    broker_url = os.environ['REDIS_URL']
    result_backend = os.environ['REDIS_URL']
 
CELERY_CONFIG = CeleryConfig
 
# Session cookie security
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE   = True   # Set False only for local HTTP dev
SESSION_COOKIE_SAMESITE = 'Strict'
 
# Disable public signup
PUBLIC_ROLE_LIKE = None
WTF_CSRF_ENABLED = True


