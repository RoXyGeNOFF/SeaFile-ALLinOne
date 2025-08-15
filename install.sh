#!/usr/bin/env bash
set -e

# Проверка на наличие .env
if [ ! -f ".env" ]; then
  echo "❌ Файл .env не найден! Скопируйте .env.example и заполните свои значения:"
  echo "cp .env.example .env && nano .env"
  exit 1
fi

# Загружаем переменные
set -o allexport
source .env
set +o allexport

echo "🚀 Установка Seafile (Docker) для локальной сети"
echo "   Админ: $SEAFILE_ADMIN_EMAIL, HTTPS: https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT"

# Устанавливаем Docker при необходимости
if ! command -v docker &>/dev/null; then
  echo "📦 Устанавливаю Docker..."
  curl -fsSL https://get.docker.com | sh
fi

# Устанавливаем docker compose plugin при необходимости
if ! docker compose version &>/dev/null; then
  echo "🔩 docker compose plugin отсутствует. Попробую установить..."
  if [ -x /usr/bin/apt ]; then
    sudo apt update && sudo apt -y install docker-compose-plugin
  else
    echo "⚠️ Установите docker compose plugin вручную согласно вашей ОС."
  fi
fi

# Генерируем самоподписанный сертификат с SAN=IP
mkdir -p certs
OPENSSL_CONF_FILE=certs/openssl.cnf
cat > "$OPENSSL_CONF_FILE" <<EOF
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
C = RU
ST = Local
L = Local
O = Local
OU = IT
CN = $SEAFILE_SERVER_HOSTNAME

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $LOCAL_IP
DNS.1 = $SEAFILE_SERVER_HOSTNAME
EOF

if [ ! -f certs/selfsigned.crt ] || [ ! -f certs/selfsigned.key ]; then
  echo "🔐 Генерирую самоподписанный сертификат для $SEAFILE_SERVER_HOSTNAME ($LOCAL_IP)..."
  openssl req -x509 -nodes -days 3650 -newkey rsa:4096     -keyout certs/selfsigned.key     -out certs/selfsigned.crt     -config "$OPENSSL_CONF_FILE"
else
  echo "🔐 Сертификаты уже существуют, пропускаю генерацию."
fi

# Поднимаем контейнеры
echo "🐳 Запускаю docker compose..."
docker compose up -d

echo "⏳ Жду инициализации Seafile (это может занять 15-60 сек)."
for i in {1..60}; do
  if [ -d "seafile/conf" ]; then
    break
  fi
  sleep 2
done

# Прописываем внешние URLs и заголовки для работы за nginx+https
CONF_DIR="seafile/conf"
mkdir -p "$CONF_DIR"

# ccnet.conf
CCNET_CONF="$CONF_DIR/ccnet.conf"
if [ ! -f "$CCNET_CONF" ]; then
  echo "[General]" > "$CCNET_CONF"
fi
if ! grep -q '^SERVICE_URL' "$CCNET_CONF"; then
  echo "SERVICE_URL = https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT" >> "$CCNET_CONF"
else
  sed -i "s#^SERVICE_URL.*#SERVICE_URL = https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT#" "$CCNET_CONF"
fi

# seahub_settings.py
SEAHUB_SETTINGS="$CONF_DIR/seahub_settings.py"
touch "$SEAHUB_SETTINGS"
if ! grep -q 'SECURE_PROXY_SSL_HEADER' "$SEAHUB_SETTINGS"; then
  cat >> "$SEAHUB_SETTINGS" <<PYCONF

# --- Auto-added by install.sh ---
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
FILE_SERVER_ROOT = 'https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT/seafhttp'
CSRF_TRUSTED_ORIGINS = ['https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT']
PYCONF
fi

echo "🔁 Перезапускаю контейнеры для применения конфигурации..."
docker compose restart seafile nginx

echo "✅ Seafile установлен и доступен по адресу: https://$SEAFILE_SERVER_HOSTNAME:$HTTPS_PORT"
echo "   Логин администратора: $SEAFILE_ADMIN_EMAIL"
echo "   Пароль администратора: $SEAFILE_ADMIN_PASSWORD"

echo ""
echo "💖 Поддержать разработчика (USDT TRC20)"
echo "Адрес: TDb2rmYkYGoX2o322JmPR12oAUJbkgtaWg"
echo "QR-код сохранён в файле donate_qr.jpeg"

# Попробовать открыть QR-код автоматически
if command -v xdg-open &>/dev/null; then
  xdg-open donate_qr.jpeg || true
elif command -v open &>/dev/null; then
  open donate_qr.jpeg || true
fi
