#!/bin/bash
set -eu

INSTALL_DIR="/opt/1cv8/x86_64/${SERVER_VERSION}"

# Запускаем RAS в фоне
"${INSTALL_DIR}/ras" cluster &

# Запускаем агент кластера (основной процесс)
exec "${INSTALL_DIR}/ragent" \
  -d /home/usr1cv8/.1cv8/1C/1cv8 \
  -port 1540 \
  -regport 1541 \
  -range 1560:1591