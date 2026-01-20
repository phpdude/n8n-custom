# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py
RUN python3 --version

# ---- main ----
FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    \
    # Community nodes (нужно, если ставишь не-verified/через npm вручную)
    N8N_COMMUNITY_PACKAGES_ENABLED="true" \
    N8N_UNVERIFIED_PACKAGES_ENABLED="true" \
    \
    # Разрешаем импорты в Code node (модули берутся из n8n/node_modules)
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib,@pdf-lib/fontkit,xlsx" \
    NODE_FUNCTION_ALLOW_BUILTIN="*" \
    \
    # Подсказка n8n где искать кастом-экстеншены/ноды (полезно, не мешает)
    N8N_CUSTOM_EXTENSIONS="/home/node/.n8n/nodes/node_modules"

USER root

# 1) Устанавливаем npm-пакеты для Code node туда, где n8n реально их ищет:
#    .../n8n/node_modules (см. доку про modules in Code node)
RUN set -eux; \
  cd /usr/local/lib/node_modules/n8n; \
  npm install --omit=dev --no-fund --no-audit \
    pdf-lib \
    @pdf-lib/fontkit \
    xlsx; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/n8n/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/n8n/node_modules/@pdf-lib/fontkit/package.json; \
  test -f /usr/local/lib/node_modules/n8n/node_modules/xlsx/package.json

# 2) Готовим директорию под community nodes в data-dir n8n
RUN set -eux; \
  mkdir -p /home/node/.n8n/nodes; \
  chown -R node:node /home/node/.n8n

# 3) Просто переносим python runtime (как у тебя)
COPY --from=py /usr/local/ /usr/local/
COPY --from=py /usr/lib/ /usr/lib/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version

USER node

# 4) ВАЖНО: ставим community node при старте контейнера, чтобы:
#    - если /home/node/.n8n примонтирован volume -> пакет реально окажется внутри volume
#    - если без volume -> тоже ок
#
#    Делается через CMD, чтобы не ломать ENTRYPOINT базового образа.
CMD sh -lc '\
  set -euo pipefail; \
  mkdir -p /home/node/.n8n/nodes; \
  if [ ! -d "/home/node/.n8n/nodes/node_modules/@custom-js/n8n-nodes-pdf-toolkit" ]; then \
    cd /home/node/.n8n/nodes; \
    [ -f package.json ] || npm init -y >/dev/null 2>&1; \
    npm install --omit=dev --no-fund --no-audit @custom-js/n8n-nodes-pdf-toolkit; \
  fi; \
  exec n8n \
'
