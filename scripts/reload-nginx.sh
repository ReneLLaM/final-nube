#!/bin/bash

################################################################################
# SCRIPT PARA RECARGAR NGINX
# Recarga la configuración de Nginx para aplicar cambios de upstream
# Uso: ./reload-nginx.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/nginx-reload.log"

# Crear directorio de logs si no existe
mkdir -p "${SCRIPT_DIR}/logs"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[${TIMESTAMP}] Recargando configuración de Nginx..." >> "$LOG_FILE"

# Verificar que Nginx está corriendo
if ! docker ps --filter "name=chat_nginx" --filter "status=running" | grep -q chat_nginx; then
    echo "[${TIMESTAMP}] ERROR: Nginx no está corriendo" >> "$LOG_FILE"
    exit 1
fi

# Recargar Nginx
docker exec chat_nginx nginx -s reload 2>/dev/null

if [ $? -eq 0 ]; then
    echo "[${TIMESTAMP}] ✅ Nginx recargado exitosamente" >> "$LOG_FILE"
    echo "✅ Nginx recargado exitosamente"
    exit 0
else
    echo "[${TIMESTAMP}] ❌ Error al recargar Nginx" >> "$LOG_FILE"
    echo "❌ Error al recargar Nginx"
    exit 1
fi
