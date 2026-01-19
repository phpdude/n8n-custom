FROM ghcr.io/n8n-io/n8n:latest

# ----------------------------
# Global env (applies to ALL processes, including task-runner)
# ----------------------------
ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    NODE_PATH="/opt/n8n-external/node_modules" \
    PATH="/home/node/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    CODE_ENABLE_STDOUT="true" \
    NO_COLOR="1"

# ----------------------------
# Install external npm deps in a clean, stable location
# ----------------------------
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

# ----------------------------
# Ensure env is present for entrypoint + child processes
# (task-runner gets the same NODE_PATH etc.)
# ----------------------------
USER root
RUN printf '%s\n' \
'#!/bin/sh' \
'export GENERIC_TIMEZONE="${GENERIC_TIMEZONE}"' \
'export N8N_PROXY_HOPS="${N8N_PROXY_HOPS}"' \
'export NODE_FUNCTION_ALLOW_EXTERNAL="${NODE_FUNCTION_ALLOW_EXTERNAL}"' \
'export NODE_PATH="${NODE_PATH}"' \
'export PATH="${PATH}"' \
'export N8N_LOG_LEVEL="${N8N_LOG_LEVEL}"' \
'export N8N_LOG_FORMAT="${N8N_LOG_FORMAT}"' \
'export N8N_LOG_OUTPUT="${N8N_LOG_OUTPUT}"' \
'export CODE_ENABLE_STDOUT="${CODE_ENABLE_STDOUT}"' \
'export NO_COLOR="${NO_COLOR}"' \
'exec /docker-entrypoint.sh "$@"' \
> /custom-entrypoint.sh && chmod +x /custom-entrypoint.sh

USER node
WORKDIR /home/node

ENTRYPOINT ["/custom-entrypoint.sh"]
CMD ["n8n"]
