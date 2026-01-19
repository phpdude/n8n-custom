FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    NO_COLOR="1" \
    N8N_RUNNERS_ENABLED="true" \
    N8N_RUNNERS_MODE="internal" \
    N8N_RUNNERS_NODE_PATH="/opt/n8n-external/node_modules"

USER root

# 1) Ставим pdf-lib в /opt/n8n-external (это и будет node_path для runner)
RUN set -eux; \
  mkdir -p /opt/n8n-external; \
  npm install --omit=dev --no-fund --no-audit --prefix /opt/n8n-external pdf-lib; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /opt/n8n-external/node_modules/pdf-lib/package.json; \
  chown -R node:node /opt/n8n-external

# 2) Делаем единый NODE_PATH, добавляя DHI global (без хардкода версии)
RUN set -eux; \
  DHI_GLOBAL="$(ls -d /opt/nodejs/node-v*/lib/node_modules | head -n 1)"; \
  echo "NODE_PATH=/opt/n8n-external/node_modules:${DHI_GLOBAL}" >> /etc/environment

# (опционально) на всякий случай фикс прав на /tmp, если где-то реально readonly/кривые perms
RUN set -eux; \
  mkdir -p /tmp; chmod 1777 /tmp

USER node
