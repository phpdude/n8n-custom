FROM ghcr.io/n8n-io/n8n:latest

# --- root: ставим python ---
USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     python3 \
     python3-pip \
     python3-venv \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# --- готовим каталоги ---
RUN mkdir -p /home/node/.n8n /home/node/.npm-cache \
  && chown -R node:node /home/node/.n8n /home/node/.npm-cache

# --- node user ---
USER node
ENV HOME=/home/node
ENV NPM_CONFIG_CACHE=/home/node/.npm-cache
WORKDIR /home/node/.n8n

# --- валидный package.json (npm init в .n8n нельзя) ---
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

# --- JS зависимости ---
RUN npm install --omit=dev --no-fund --no-audit pdf-lib \
  && npm cache clean --force

# --- финальный workdir ---
WORKDIR /home/node
