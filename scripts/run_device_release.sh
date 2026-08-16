#!/usr/bin/env bash
# То же, что scripts/run_device.sh, но в RELEASE-режиме.
#
# Отличия релиза:
#  - без API_URL приложение показывает экран «Сборка без адреса сервера»
#    (см. lib/main.dart _resolveBaseUrl), поэтому адрес передаём всегда;
#  - по умолчанию берём Bonjour-хостнейм Мака (локальный бэкенд на :8000),
#    домен .local не попадает под ATS, так что http работает и в релизе;
#  - для проверки против прода: API_URL=https://<домен> scripts/run_device_release.sh
#  - релизная сборка подписывается по-настоящему: остатки iCloud-атрибутов
#    ломают CodeSign («detritus not allowed»), поэтому чистим xattr.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

HOST="$(scutil --get LocalHostName).local"
API_URL="${API_URL:-http://${HOST}:8000}"

echo "MODE=release"
echo "API_URL=${API_URL}"

# Снимаем расширенные атрибуты, иначе codesign падает на «detritus not allowed».
xattr -cr "${PROJECT_ROOT}" 2>/dev/null || true

# Устройство видно и по USB, и по Wi-Fi одновременно (одинаковое имя
# "iPhone(whynicky)"), из-за чего Flutter иногда выбирает беспроводное
# подключение — оно менее стабильно. Явно берём проводное по device id.
DEVICE_ID="$(flutter devices 2>/dev/null | grep 'iPhone(whynicky) (mobile)' | awk -F'•' '{print $2}' | xargs)"

if [ -n "${DEVICE_ID:-}" ]; then
  exec flutter run --release -d "${DEVICE_ID}" --dart-define=API_URL="${API_URL}" "$@"
else
  exec flutter run --release --dart-define=API_URL="${API_URL}" "$@"
fi
