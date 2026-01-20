# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py
RUN python3 --version

# ---- main ----
FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="*" \
    NODE_PATH="/usr/local/lib/node_modules" \
    \
    N8N_COMMUNITY_PACKAGES_ENABLED="true" \
    N8N_UNVERIFIED_PACKAGES_ENABLED="true" \
    N8N_CUSTOM_EXTENSIONS="/home/node/.n8n/custom/node_modules"

USER root

# 1) Либы для Code node — как в твоем первом Dockerfile
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local \
    pdf-lib \
    @pdf-lib/fontkit \
    xlsx; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/@pdf-lib/fontkit/package.json; \
  test -f /usr/local/lib/node_modules/xlsx/package.json

# 2) Директория под custom/community nodes
RUN set -eux; \
  mkdir -p /home/node/.n8n/custom; \
  chown -R node:node /home/node/.n8n

# 3) Python runtime
COPY --from=py /usr/local/ /usr/local/
COPY --from=py /usr/lib/ /usr/lib/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version

# 4) Prestart (kaniko-safe, без heredoc)
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
'  npm install --omit=dev --no-fund --no-audit @custom-js/n8n-nodes-pdf-toolkit' \
'fi' \
'' \
'# запускаем реальную команду из CMD' \
'exec "$@"' \
  > /usr/local/bin/n8n-prestart.sh; \
  chmod +x /usr/local/bin/n8n-prestart.sh

USER node

ENTRYPOINT ["/usr/local/bin/n8n-prestart.sh"]

# ВАЖНО: запускаем n8n по явному пути, а не через "n8n" в PATH
CMD ["node", "/usr/local/lib/node_modules/n8n/bin/n8n"]
