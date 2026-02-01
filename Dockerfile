# ---- stage: python donor (glibc) ----
# IMPORTANT: n8n official image is Debian/Ubuntu-based (glibc),
# so DO NOT copy Python from Alpine/musl (it will break).
FROM python:3.13-slim AS py
RUN python3 --version && pip3 --version

# ---- main ----
FROM ghcr.io/n8n-io/n8n:2.4.4

ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    N8N_RUNNERS_ENABLED="true" \
    NODES_EXCLUDE="[]" \
    N8N_FILESYSTEM_ALLOWED_PATHS="/home/node/.n8n/tmp,/tmp/merge" \
    N8N_RESTRICT_FILE_ACCESS_TO="" \
    N8N_RUNNERS_ALLOW_PROTOTYPE_MUTATION="true" \
    \
    # Code node libs
    NODE_FUNCTION_ALLOW_BUILTIN="*" \
    NODE_FUNCTION_ALLOW_EXTERNAL="*" \
    NODE_PATH="/usr/local/lib/node_modules" \
    \
    # community nodes
    N8N_COMMUNITY_PACKAGES_ENABLED="true" \
    N8N_UNVERIFIED_PACKAGES_ENABLED="true"

USER root

# 0) System deps for:
# - ffmpeg (merge video/audio, burn-in text/subtitles)
# - fonts + fontconfig (ffmpeg drawtext)
# - ca-certificates/curl (downloads)
RUN set -eux; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ffmpeg \
    fontconfig \
    fonts-dejavu-core \
    fonts-noto-core \
    ca-certificates \
    curl \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  ffmpeg -version; \
  fc-cache -f

# 1) LIBS FOR CODE NODE — AS YOU HAD
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit --prefix /usr/local \
    pdf-lib \
    @pdf-lib/fontkit \
    xlsx; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /usr/local/lib/node_modules/pdf-lib/package.json; \
  test -f /usr/local/lib/node_modules/@pdf-lib/fontkit/package.json; \
  test -f /usr/local/lib/node_modules/xlsx/package.json

# 2) Prepare user folder (volume may overwrite, but keep perms sane)
RUN set -eux; \
  mkdir -p /home/node/.n8n /home/node/.n8n/tmp /home/node/.n8n/nodes /tmp/merge; \
  chown -R node:node /home/node/.n8n /tmp/merge

# 3) Python runtime (glibc-compatible)
# Copy only /usr/local from python donor (bin/python3 + libs + pip)
COPY --from=py /usr/local/ /usr/local/

RUN set -eux; \
  python3 --version; \
  python --version; \
  pip3 --version

# 4) Prestart: install community package where n8n actually searches it: ~/.n8n/nodes
RUN set -eux; \
  printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'' \
'# ensure nodes dir exists (volume can overwrite)' \
'mkdir -p /home/node/.n8n/nodes' \
'chown -R node:node /home/node/.n8n/nodes || true' \
'' \
'PKG="@custom-js/n8n-nodes-pdf-toolkit"' \
'PKGDIR="/home/node/.n8n/nodes/node_modules/@custom-js/n8n-nodes-pdf-toolkit"' \
'' \
'if [ ! -d "$PKGDIR" ]; then' \
'  echo "[prestart] installing community package: $PKG"' \
'  cd /home/node/.n8n/nodes' \
'  npm install --omit=dev --no-fund --no-audit "$PKG"' \
'fi' \
'' \
'exec "$@"' \
  > /usr/local/bin/n8n-prestart.sh; \
  chmod +x /usr/local/bin/n8n-prestart.sh

# Your script
COPY scripts/strict-merge.js /opt/strict-merge.js
RUN chmod +x /opt/strict-merge.js

USER node

ENTRYPOINT ["/usr/local/bin/n8n-prestart.sh"]
CMD ["node", "/usr/local/lib/node_modules/n8n/bin/n8n"]
