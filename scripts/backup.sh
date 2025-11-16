#!/bin/bash

################################################################################
# Script de Backup para Chat en Tiempo Real
# Realiza backups de la base de datos PostgreSQL
# Uso: ./backup.sh
################################################################################

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${PROJECT_DIR}/backups"
LOG_FILE="${PROJECT_DIR}/logs/backup.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/chatdb_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=30

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"
mkdir -p "${PROJECT_DIR}/logs"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Iniciando backup de base de datos ==="

# Verificar que el contenedor de BD está corriendo
if ! docker ps --filter "name=chat_db" --format "{{.Names}}" | grep -q "chat_db"; then
    log "ERROR: Contenedor chat_db no está corriendo"
    exit 1
fi

# Realizar backup
log "Realizando backup a: $BACKUP_FILE"

docker exec chat_db pg_dump -U chatuser -d chatdb | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "✓ Backup completado exitosamente - Tamaño: $SIZE"
else
    log "ERROR: Fallo en el backup"
    exit 1
fi

# Limpiar backups antiguos
log "Limpiando backups más antiguos de $RETENTION_DAYS días"
find "$BACKUP_DIR" -name "chatdb_*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Contar backups disponibles
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/chatdb_*.sql.gz 2>/dev/null | wc -l)
log "Backups disponibles: $BACKUP_COUNT"

log "=== Backup completado ==="
