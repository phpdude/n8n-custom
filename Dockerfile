# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py

# (опционально) убедимся что python есть
RUN python3 --version

FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib,@pdf-lib/fontkit,xlsx,@custom-js/n8n-nodes-pdf-toolkit.html2Pdf"

# ENV N8N_LOG_LEVEL="debug" \
#     N8N_LOG_FORMAT="json" \
#     N8N_LOG_OUTPUT="console"

USER root

RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local pdf-lib @pdf-lib/fontkit xlsx @custom-js/n8n-nodes-pdf-toolkit.html2Pdf; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/@pdf-lib/fontkit/package.json

# Просто переносим python runtime
COPY --from=py /usr/local/ /usr/local/
COPY --from=py /usr/lib/ /usr/lib/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version
# Smoke test
RUN set -eux; \
  python3 --version; \
  python --version
  
USER node
