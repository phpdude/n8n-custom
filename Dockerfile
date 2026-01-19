FROM ghcr.io/n8n-io/n8n:latest

USER root

# Папка для внешних модулей (не трогаем n8n monorepo)
RUN mkdir -p /opt/n8n-external/node_modules \
  && chown -R node:node /opt/n8n-external

USER node
ENV HOME=/home/node

# Ставим pdf-lib в /opt/n8n-external/node_modules
RUN npm_config_prefix=/opt/n8n-external \
  npm install --omit=dev --no-fund --no-audit --prefix /opt/n8n-external pdf-lib \
  && node -p "require('/opt/n8n-external/node_modules/pdf-lib') && 'pdf-lib installed'" >/dev/null

# ВАЖНО: добавляем путь, который увидит и n8n, и task-runner
ENV NODE_PATH=/opt/n8n-external/node_modules

# (опционально) чтобы Code node тоже видел
ENV NODE_FUNCTION_ALLOW_EXTERNAL=pdf-lib

# вернуть дефолтный workdir
WORKDIR /home/node
