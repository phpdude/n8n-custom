# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py
RUN python3 --version

# ---- main ----
FROM ghcr.io/n8n-io/n8n:2.4.4

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    N8N_RUNNERS_ENABLED="false" \
    \
    # Code node libs: как у тебя было
    NODE_FUNCTION_ALLOW_EXTERNAL="*" \
    NODE_PATH="/usr/local/lib/node_modules" \
    \
    # community nodes
    N8N_COMMUNITY_PACKAGES_ENABLED="true" \
    N8N_UNVERIFIED_PACKAGES_ENABLED="true"

USER root

# 1) ЛИБЫ ДЛЯ CODE NODE — РОВНО КАК В ТВОЕМ ПЕРВОМ DOCKERFILE
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local \
    pdf-lib \
    @pdf-lib/fontkit \
    xlsx; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/@pdf-lib/fontkit/package.json; \
  test -f /usr/local/lib/node_modules/xlsx/package.json

# 2) Готовим user-folder (на volume он всё равно может перезаписаться)
RUN set -eux; \
  mkdir -p /home/node/.n8n; \
  chown -R node:node /home/node/.n8n

# 3) Python runtime (как у тебя)
COPY --from=py /usr/local/ /usr/local/
COPY --from=py /usr/lib/ /usr/lib/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version

# 4) Prestart: ставим COMMUNITY PACKAGE туда, где n8n его реально ищет: ~/.n8n/nodes
RUN set -eux; \
  printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'' \
'mkdir -p /home/node/.n8n/nodes' \
'' \
'if [ ! -d "/home/node/.n8n/nodes/node_modules/@custom-js/n8n-nodes-pdf-toolkit" ]; then' \
'  echo "[prestart] installing community package: @custom-js/n8n-nodes-pdf-toolkit"' \
'  cd /home/node/.n8n/nodes' \
'  npm install --omit=dev --no-fund --no-audit @custom-js/n8n-nodes-pdf-toolkit' \
'fi' \
'' \
'exec "$@"' \
  > /usr/local/bin/n8n-prestart.sh; \
  chmod +x /usr/local/bin/n8n-prestart.sh

USER node

ENTRYPOINT ["/usr/local/bin/n8n-prestart.sh"]
CMD ["node", "/usr/local/lib/node_modules/n8n/bin/n8n"]
