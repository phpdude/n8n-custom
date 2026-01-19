# ---- stage: python donor (alpine/musl) ----
FROM python:3.13-alpine AS py

# (опционально) убедимся что python есть
RUN python3 --version

FROM ghcr.io/n8n-io/n8n:latest

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib"

# ENV N8N_LOG_LEVEL="debug" \
#     N8N_LOG_FORMAT="json" \
#     N8N_LOG_OUTPUT="console"

USER root

RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local pdf-lib; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json

# ---- bring python runtime from donor ----
# Copy python binaries
COPY --from=py /usr/local/bin/python3 /usr/local/bin/python3
COPY --from=py /usr/local/bin/python /usr/local/bin/python
COPY --from=py /usr/local/bin/pip3 /usr/local/bin/pip3
COPY --from=py /usr/local/bin/pip /usr/local/bin/pip

# Copy python stdlib + dyn libs (musl-compatible because donor is alpine)
COPY --from=py /usr/local/lib/python3.13 /usr/local/lib/python3.13
COPY --from=py /usr/local/lib/libpython3.13.so* /usr/local/lib/ 2>/dev/null || true

# Some builds place libpython elsewhere; also copy /usr/lib just in case (small in alpine)
COPY --from=py /usr/lib/ /usr/lib/

# Smoke test
RUN set -eux; \
  python3 --version; \
  python --version
  
USER node
