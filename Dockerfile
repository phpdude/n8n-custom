FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    NO_COLOR="1"

USER root

RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local pdf-lib; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json

USER node
