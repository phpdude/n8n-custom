FROM ghcr.io/n8n-io/n8n:latest

USER root

# 1) Ставим pdf-lib туда, откуда внутренний task-runner реально резолвит require()
#    Node resolution идет от dist/start.js -> ../ (package root) -> ./node_modules
RUN set -eux; \
  RUNNER_DIR="/usr/local/lib/node_modules/n8n/node_modules/@n8n/task-runner"; \
  test -d "$RUNNER_DIR" || (echo "Task runner dir not found: $RUNNER_DIR" && exit 1); \
  npm install --prefix "$RUNNER_DIR" --omit=dev --no-fund --no-audit pdf-lib; \
  node -e "process.chdir('$RUNNER_DIR/dist'); require('pdf-lib'); console.log('pdf-lib OK from task-runner/dist')"

USER node

# (не обязательно) можно задать NODE_PATH, но после установки выше оно уже не нужно
# ENV NODE_PATH=/home/node/.n8n/node_modules
