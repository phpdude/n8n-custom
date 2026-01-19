FROM ghcr.io/n8n-io/n8n:latest

# -----------------------------
# Подготовка каталогов (root)
# -----------------------------
USER root

RUN mkdir -p /home/node/.n8n \
  && chown -R node:node /home/node/.n8n

# -----------------------------
# Установка JS-зависимостей
# -----------------------------
USER node
ENV HOME=/home/node
WORKDIR /home/node/.n8n

# ВАЖНО: npm init в .n8n делать нельзя (invalid name),
# поэтому создаём package.json вручную
RUN if [ ! -f package.json ]; then \
      printf '%s\n' \
        '{' \
        '  "name": "n8n-user-data",' \
        '  "private": true,' \
        '  "version": "1.0.0",' \
        '  "description": "n8n user data deps",' \
        '  "dependencies": {}' \
        '}' > package.json; \
    fi

# Устанавливаем pdf-lib локально
RUN npm install --omit=dev --no-fund --no-audit pdf-lib \
  && npm cache clean --force

# -----------------------------
# Возвращаем рабочую директорию
# -----------------------------
WORKDIR /home/node
