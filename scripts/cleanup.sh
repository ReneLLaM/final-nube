#!/bin/bash

################################################################################
# Script de Limpieza para Chat en Tiempo Real
# Limpia logs antiguos y optimiza la base de datos
# Uso: ./cleanup.sh
################################################################################

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/cleanup.log"
RETENTION_DAYS=30

# Crear directorio de logs si no existe
mkdir -p "$LOG_DIR"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Iniciando limpieza del sistema ==="

# 1. Limpiar logs antiguos
log "Limpiando logs más antiguos de $RETENTION_DAYS días"
find "$LOG_DIR" -name "*.log" -mtime +$RETENTION_DAYS -delete
log "✓ Logs antiguos eliminados"

# 2. Comprimir logs del mes anterior
log "Comprimiendo logs del mes anterior"
find "$LOG_DIR" -name "*.log" -mtime +7 ! -name "*.gz" -exec gzip {} \;
log "✓ Logs comprimidos"

# 3. Limpiar registros de conexiones desconectadas
log "Limpiando registros de conexiones antiguas de la BD"
if docker ps --filter "name=chat_db" --format "{{.Names}}" | grep -q "chat_db"; then
    docker exec chat_db psql -U chatuser -d chatdb -c \
        "DELETE FROM active_connections WHERE disconnected_at < NOW() - INTERVAL '7 days';" \
        2>/dev/null || log "Advertencia: No se pudieron limpiar conexiones antiguas"
    log "✓ Conexiones antiguas eliminadas"
else
    log "Advertencia: Base de datos no disponible"
fi

# 4. Limpiar mensajes muy antiguos (opcional - comentado por defecto)
# log "Limpiando mensajes más antiguos de 90 días"
# docker exec chat_db psql -U chatuser -d chatdb -c \
#     "DELETE FROM messages WHERE created_at < NOW() - INTERVAL '90 days';" \
#     2>/dev/null || log "Advertencia: No se pudieron limpiar mensajes antiguos"

# 5. Optimizar base de datos
log "Optimizando base de datos"
if docker ps --filter "name=chat_db" --format "{{.Names}}" | grep -q "chat_db"; then
    docker exec chat_db psql -U chatuser -d chatdb -c "VACUUM ANALYZE;" \
        2>/dev/null || log "Advertencia: No se pudo optimizar la BD"
    log "✓ Base de datos optimizada"
fi

# 6. Limpiar imágenes y contenedores de Docker no utilizados
log "Limpiando recursos de Docker no utilizados"
docker image prune -f --filter "until=72h" > /dev/null 2>&1 || true
docker container prune -f --filter "until=72h" > /dev/null 2>&1 || true
log "✓ Recursos de Docker limpiados"

# 7. Mostrar estadísticas
log "=== Estadísticas de Limpieza ==="
log "Espacio usado en logs: $(du -sh "$LOG_DIR" 2>/dev/null || echo 'N/A')"
log "Backups disponibles: $(ls -1 "${PROJECT_DIR}/backups"/*.sql.gz 2>/dev/null | wc -l)"
log "Contenedores Docker: $(docker ps -a --format "{{.Names}}" | wc -l)"

log "=== Limpieza completada ==="
