FROM ghcr.io/n8n-io/n8n:latest

# 1) Включаем дебаг и разрешаем модуль
# 2) Расширяем NODE_PATH так, чтобы:
#    - n8n видел /opt/n8n-external/node_modules (как сейчас)
#    - runner видел DHI global node_modules (/opt/nodejs/...)
#    - runner также видел стандартные пути (оставляем как есть)
ENV GENERIC_TIMEZONE="Europe/Madrid" \
    N8N_PROXY_HOPS="1" \
    NODE_FUNCTION_ALLOW_EXTERNAL="pdf-lib" \
    N8N_LOG_LEVEL="debug" \
    N8N_LOG_FORMAT="json" \
    N8N_LOG_OUTPUT="console" \
    NO_COLOR="1"

USER root

# Ставим pdf-lib в то место, куда DHI реально ставит global npm пакеты
# (и где базовый Dockerfile n8n ожидает их видеть)
RUN set -eux; \
  npm install -g --omit=dev --no-fund --no-audit pdf-lib; \
  npm cache clean --force >/dev/null 2>&1; \
  test -f /opt/nodejs/node-v*/lib/node_modules/pdf-lib/package.json; \
  echo "pdf-lib installed into DHI global node_modules"

# ВАЖНО: NODE_PATH должен быть у обоих процессов (n8n + runner)
# Поэтому делаем единый NODE_PATH, который включает и /opt/n8n-external,
# и DHI global node_modules.
# (используем wildcard только на этапе RUN, а ENV задаём конкретно через shell)
RUN set -eux; \
  DHI_GLOBAL="$(ls -d /opt/nodejs/node-v*/lib/node_modules | head -n 1)"; \
  echo "DHI_GLOBAL=$DHI_GLOBAL"; \
  printf '%s\n' "export DHI_GLOBAL=$DHI_GLOBAL" > /etc/profile.d/dhi_global.sh

# Задаём NODE_PATH статически через переменную, которую runner реально увидит:
# Мы не можем использовать $(...) в ENV, поэтому жёстко дублируем паттерн версии,
# а версию берём из уже существующего NODE_VERSION внутри образа.
# Самый надёжный вариант: выставить N8N_RUNNERS_NODE_PATH на наш /opt/n8n-external
# и добавить DHI global в NODE_PATH.
ENV NODE_PATH="/opt/n8n-external/node_modules:/opt/nodejs/node-v22.21.1/lib/node_modules:/usr/local/lib/node_modules:/usr/local/node_modules:/usr/node_modules:/node_modules" \
    N8N_RUNNERS_NODE_PATH="/opt/n8n-external/node_modules"

USER node
