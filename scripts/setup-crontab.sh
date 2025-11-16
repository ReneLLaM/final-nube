#!/bin/bash

################################################################################
# Script de Configuración de Crontab
# Configura automáticamente los trabajos cron para autoescalabilidad
# Uso: ./setup-crontab.sh
################################################################################

set -e

# Obtener directorio del proyecto
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOSCALE_SCRIPT="${PROJECT_DIR}/scripts/autoscale.sh"
BACKUP_SCRIPT="${PROJECT_DIR}/scripts/backup.sh"
CLEANUP_SCRIPT="${PROJECT_DIR}/scripts/cleanup.sh"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Configurador de Crontab para Chat en Tiempo Real ===${NC}\n"

# Verificar si los scripts existen
if [ ! -f "$AUTOSCALE_SCRIPT" ]; then
    echo -e "${RED}Error: Script de autoescalabilidad no encontrado en $AUTOSCALE_SCRIPT${NC}"
    exit 1
fi

# Hacer scripts ejecutables
chmod +x "$AUTOSCALE_SCRIPT"
if [ -f "$BACKUP_SCRIPT" ]; then
    chmod +x "$BACKUP_SCRIPT"
fi
if [ -f "$CLEANUP_SCRIPT" ]; then
    chmod +x "$CLEANUP_SCRIPT"
fi

# Crear archivo temporal para nuevos cron jobs
TEMP_CRON=$(mktemp)
trap "rm -f $TEMP_CRON" EXIT

# Exportar crontab actual (si existe)
crontab -l > "$TEMP_CRON" 2>/dev/null || true

# Función para añadir cron job si no existe
add_cron_job() {
    local schedule=$1
    local command=$2
    local description=$3

    if grep -q "$command" "$TEMP_CRON" 2>/dev/null; then
        echo -e "${YELLOW}✓ Job ya existe: $description${NC}"
    else
        echo "$schedule $command" >> "$TEMP_CRON"
        echo -e "${GREEN}✓ Job añadido: $description${NC}"
    fi
}

echo -e "${BLUE}Configurando trabajos cron...${NC}\n"

# 1. Monitoreo y autoescalabilidad cada minuto
add_cron_job "* * * * *" \
    "$AUTOSCALE_SCRIPT --monitor >> ${PROJECT_DIR}/logs/autoscale.log 2>&1" \
    "Monitoreo y autoescalabilidad (cada minuto)"

# 2. Backup de base de datos cada 6 horas
add_cron_job "0 */6 * * *" \
    "$BACKUP_SCRIPT >> ${PROJECT_DIR}/logs/backup.log 2>&1" \
    "Backup de base de datos (cada 6 horas)"

# 3. Limpieza de logs antiguos cada día a las 2 AM
add_cron_job "0 2 * * *" \
    "$CLEANUP_SCRIPT >> ${PROJECT_DIR}/logs/cleanup.log 2>&1" \
    "Limpieza de logs (diariamente a las 2 AM)"

# 4. Verificación de salud cada 5 minutos
add_cron_job "*/5 * * * *" \
    "curl -s http://localhost/health > /dev/null 2>&1 || echo 'Health check failed' >> ${PROJECT_DIR}/logs/health.log" \
    "Verificación de salud (cada 5 minutos)"

# 5. Reporte de métricas cada hora
add_cron_job "0 * * * *" \
    "$AUTOSCALE_SCRIPT --status >> ${PROJECT_DIR}/logs/metrics_hourly.log 2>&1" \
    "Reporte de métricas (cada hora)"

# 6. Reinicio de servicios cada domingo a las 3 AM
add_cron_job "0 3 * * 0" \
    "cd $PROJECT_DIR && docker-compose restart >> ${PROJECT_DIR}/logs/restart.log 2>&1" \
    "Reinicio de servicios (cada domingo a las 3 AM)"

echo ""

# Instalar nuevo crontab
if crontab "$TEMP_CRON" 2>/dev/null; then
    echo -e "${GREEN}✓ Crontab actualizado exitosamente${NC}\n"
else
    echo -e "${RED}✗ Error al actualizar crontab${NC}"
    exit 1
fi

# Mostrar crontab actual
echo -e "${BLUE}=== Trabajos Cron Actuales ===${NC}\n"
crontab -l

echo ""
echo -e "${BLUE}=== Información Importante ===${NC}"
echo -e "${YELLOW}1. Los logs se guardarán en: ${PROJECT_DIR}/logs/${NC}"
echo -e "${YELLOW}2. Asegúrate de que Docker esté corriendo${NC}"
echo -e "${YELLOW}3. Verifica los logs regularmente para monitorear el estado${NC}"
echo -e "${YELLOW}4. Para ver el estado actual: $AUTOSCALE_SCRIPT --status${NC}"
echo -e "${YELLOW}5. Para editar crontab: crontab -e${NC}"
echo -e "${YELLOW}6. Para eliminar todos los jobs: crontab -r${NC}"
echo ""

echo -e "${GREEN}✓ Configuración completada exitosamente${NC}"
