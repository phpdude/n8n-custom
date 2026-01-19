FROM ghcr.io/n8n-io/n8n:latest

# ---- hardcode non-secret env (optional, but ok) ----
ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    NO_COLOR="1"

# ---- install pdf-lib where the internal task-runner can always resolve it ----
USER root

# IMPORTANT:
# - runner's NODE_PATH includes /usr/local/lib/node_modules
# - install there (global, non-dev)
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit pdf-lib; \
  npm cache clean --force >/dev/null 2>&1; \
  node -e "require('pdf-lib'); console.log('pdf-lib OK (global)')"

USER node
