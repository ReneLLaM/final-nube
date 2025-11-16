#!/bin/bash

################################################################################
# Script de Prueba de Estrés para Autoescalado
# Estresa la CPU del contenedor backend para probar autoescalado
# Uso: ./stress-test.sh [duración_segundos]
################################################################################

set -e

# Configuración
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION=${1:-60}  # Duración en segundos (por defecto 60)
CONTAINER_NAME="chat_backend"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PRUEBA DE ESTRÉS - AUTOESCALADO                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"

# Verificar que el contenedor existe
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo -e "${RED}✗ Error: Contenedor $CONTAINER_NAME no encontrado${NC}"
    echo -e "${YELLOW}Asegúrate de que docker-compose está corriendo:${NC}"
    echo -e "  docker compose up -d"
    exit 1
fi

echo -e "${GREEN}✓ Contenedor encontrado: $CONTAINER_NAME${NC}\n"

# Mostrar configuración actual
echo -e "${BLUE}═══ CONFIGURACIÓN ACTUAL ═══${NC}"
echo -e "Duración de prueba: ${YELLOW}${DURATION} segundos${NC}"
echo -e "Umbral CPU: ${YELLOW}50%${NC} (configurado para pruebas)"
echo -e "Cooldown scale up: ${YELLOW}30 segundos${NC}"
echo -e "Cooldown scale down: ${YELLOW}60 segundos${NC}\n"

# Mostrar estado inicial
echo -e "${BLUE}═══ ESTADO INICIAL ═══${NC}"
echo -e "Contenedores backend:"
docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}"
echo ""

# Obtener estadísticas iniciales
echo -e "${BLUE}═══ INICIANDO ESTRÉS ═══${NC}"
echo -e "Ejecutando comando de estrés en el contenedor...\n"

# Comando para estresar CPU (usa bc para cálculos)
STRESS_CMD="for i in \$(seq 1 $DURATION); do echo 'scale=10000; a(1)*8' | bc -l > /dev/null; done"

# Ejecutar estrés en background
docker exec -d $CONTAINER_NAME bash -c "$STRESS_CMD" 2>/dev/null || true

# Monitorear durante la prueba
echo -e "${YELLOW}Monitoreando durante ${DURATION} segundos...${NC}\n"

for i in $(seq 1 $DURATION); do
    # Obtener estadísticas
    STATS=$(docker stats $CONTAINER_NAME --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null || echo "N/A\tN/A")
    CPU=$(echo "$STATS" | awk '{print $1}' | sed 's/%//g')
    MEM=$(echo "$STATS" | awk '{print $2}' | sed 's/%//g')
    
    # Mostrar progreso
    printf "\r[%3d/%3d] CPU: %6s | MEM: %6s | Contenedores: " "$i" "$DURATION" "$CPU" "$MEM"
    
    # Contar contenedores backend
    COUNT=$(docker ps --filter "name=chat_backend" --format "{{.Names}}" | wc -l)
    printf "%d" "$COUNT"
    
    sleep 1
done

echo -e "\n\n${GREEN}✓ Estrés completado${NC}\n"

# Mostrar estado final
echo -e "${BLUE}═══ ESTADO FINAL ═══${NC}"
echo -e "Contenedores backend después del estrés:"
docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}"
echo ""

# Mostrar estadísticas finales
echo -e "${BLUE}═══ ESTADÍSTICAS FINALES ═══${NC}"
FINAL_STATS=$(docker stats $CONTAINER_NAME --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null || echo "N/A\tN/A")
echo "CPU: $(echo "$FINAL_STATS" | awk '{print $1}')"
echo "Memoria: $(echo "$FINAL_STATS" | awk '{print $2}')"
echo ""

# Ver logs del autoescalado
echo -e "${BLUE}═══ LOGS DEL AUTOESCALADO ═══${NC}"
if [ -f "$PROJECT_DIR/logs/autoscale.log" ]; then
    echo -e "${YELLOW}Últimas líneas del log:${NC}"
    tail -20 "$PROJECT_DIR/logs/autoscale.log"
else
    echo -e "${YELLOW}No hay logs aún. Ejecuta:${NC}"
    echo -e "  ./scripts/setup-crontab.sh"
fi

echo -e "\n${GREEN}═══ PRUEBA COMPLETADA ═══${NC}\n"

# Mostrar recomendaciones
echo -e "${BLUE}📝 RECOMENDACIONES:${NC}"
echo -e "1. Ver logs en tiempo real:"
echo -e "   ${YELLOW}tail -f logs/autoscale.log${NC}"
echo -e ""
echo -e "2. Ver estadísticas de Docker:"
echo -e "   ${YELLOW}docker stats${NC}"
echo -e ""
echo -e "3. Ver contenedores:"
echo -e "   ${YELLOW}docker ps${NC}"
echo -e ""
echo -e "4. Ejecutar prueba más larga:"
echo -e "   ${YELLOW}./scripts/stress-test.sh 300${NC} (5 minutos)"
echo -e ""
