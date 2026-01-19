FROM ghcr.io/n8n-io/n8n:latest

# Global env (applies to ALL processes)
ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    NODE_PATH="/opt/n8n-external/node_modules" \
    N8N_RUNNERS_NODE_PATH="/opt/n8n-external/node_modules" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    CODE_ENABLE_STDOUT="true" \
    NO_COLOR="1"

USER root
RUN set -eux; \
    mkdir -p /opt/n8n-external; \
    chown -R node:node /opt/n8n-external

USER node
WORKDIR /opt/n8n-external

RUN set -eux; \
    if [ ! -f package.json ]; then npm init -y >/dev/null 2>&1; fi; \
    npm install --omit=dev --no-fund --no-audit pdf-lib; \
    npm cache clean --force >/dev/null 2>&1; \
    node -e "require('pdf-lib'); console.log('pdf-lib OK (build time)')"

WORKDIR /home/node
