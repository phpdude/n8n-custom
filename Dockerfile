# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py
RUN python3 --version

# ---- main ----
FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="*" \
    NODE_PATH="/usr/local/lib/node_modules" \
    N8N_COMMUNITY_PACKAGES_ENABLED="true" \
    N8N_UNVERIFIED_PACKAGES_ENABLED="true" \
    N8N_CUSTOM_EXTENSIONS="/home/node/.n8n/custom/node_modules"

USER root

# 1) libs for Code node (как у тебя было изначально)
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local \
    pdf-lib \
    @pdf-lib/fontkit \
    xlsx; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/@pdf-lib/fontkit/package.json; \
  test -f /usr/local/lib/node_modules/xlsx/package.json

# 2) custom extensions dir
RUN set -eux; \
  mkdir -p /home/node/.n8n/custom; \
  chown -R node:node /home/node/.n8n

# 3) Python runtime (как у тебя)
COPY --from=py /usr/local/ /usr/local/
COPY --from=py /usr/lib/ /usr/lib/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version

# 4) prestart script WITHOUT heredoc (kaniko-safe)
RUN set -eux; \
  printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'' \
'mkdir -p /home/node/.n8n/custom' \
'mkdir -p /home/node/.n8n/custom/node_modules' \
'' \
'if [ ! -d "/home/node/.n8n/custom/node_modules/@custom-js/n8n-nodes-pdf-toolkit" ]; then' \
'  echo "[prestart] installing community node: @custom-js/n8n-nodes-pdf-toolkit"' \
'  cd /home/node/.n8n/custom' \
'  [ -f package.json ] || npm init -y >/dev/null 2>&1' \
'  npm install --unsafe-perm --omit=dev --no-fund --no-audit @custom-js/n8n-nodes-pdf-toolkit' \
'fi' \
'' \
'exec /docker-entrypoint.sh "$@"' \
  > /usr/local/bin/n8n-prestart.sh; \
  chmod +x /usr/local/bin/n8n-prestart.sh

USER node

ENTRYPOINT ["/usr/local/bin/n8n-prestart.sh"]
CMD ["n8n"]
