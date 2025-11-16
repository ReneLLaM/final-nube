#!/bin/bash

################################################################################
# Script de Monitoreo en Tiempo Real
# Muestra métricas del autoescalado en tiempo real
# Uso: ./monitor.sh
################################################################################

set -e

# Configuración
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${PROJECT_DIR}/logs/autoscale.log"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Función para limpiar pantalla y mostrar encabezado
show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          MONITOREO EN TIEMPO REAL - AUTOESCALADO                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# Función para mostrar estadísticas
show_stats() {
    echo -e "${CYAN}═══ ESTADÍSTICAS DE CONTENEDORES ═══${NC}\n"
    
    # Mostrar contenedores backend
    echo -e "${YELLOW}Contenedores Backend:${NC}"
    BACKEND_COUNT=$(docker ps --filter "name=chat_backend" --format "{{.Names}}" | wc -l)
    docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
    echo -e "Total: ${GREEN}${BACKEND_COUNT}${NC}\n"
    
    # Estadísticas de Docker
    echo -e "${YELLOW}Uso de Recursos:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "chat_backend|chat_db|chat_frontend|chat_nginx" || echo "No hay contenedores"
    echo ""
}

# Función para mostrar logs
show_logs() {
    echo -e "${CYAN}═══ ÚLTIMOS EVENTOS DEL AUTOESCALADO ═══${NC}\n"
    
    if [ -f "$LOG_FILE" ]; then
        tail -15 "$LOG_FILE" | while IFS= read -r line; do
            if [[ $line == *"ESCAL"* ]] || [[ $line == *"SCALE"* ]]; then
                echo -e "${GREEN}$line${NC}"
            elif [[ $line == *"ERROR"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ $line == *"WARNING"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}No hay logs aún. Ejecuta: ./scripts/setup-crontab.sh${NC}"
    fi
    echo ""
}

# Función para mostrar configuración
show_config() {
    echo -e "${CYAN}═══ CONFIGURACIÓN ═══${NC}\n"
    
    CONFIG_FILE="${PROJECT_DIR}/config/autoscale.conf"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Umbrales:${NC}"
        grep "THRESHOLD\|REPLICAS\|COOLDOWN" "$CONFIG_FILE" | grep -v "^#" | while read line; do
            KEY=$(echo "$line" | cut -d'=' -f1)
            VALUE=$(echo "$line" | cut -d'=' -f2)
            echo "  $KEY = ${GREEN}${VALUE}${NC}"
        done
    fi
    echo ""
}

# Función para mostrar instrucciones
show_instructions() {
    echo -e "${CYAN}═══ INSTRUCCIONES ═══${NC}\n"
    echo -e "${YELLOW}Para probar el autoescalado:${NC}"
    echo -e "  1. En otra terminal, ejecuta:"
    echo -e "     ${GREEN}./scripts/stress-test.sh 120${NC}"
    echo -e ""
    echo -e "  2. Observa cómo se crean nuevos contenedores"
    echo -e "     cuando la CPU supera el 50%"
    echo -e ""
    echo -e "  3. Presiona Ctrl+C para salir de este monitor"
    echo ""
}

# Función principal
main() {
    show_header
    show_config
    show_instructions
    
    echo -e "${BLUE}Actualizando cada 5 segundos... (Presiona Ctrl+C para salir)${NC}\n"
    
    while true; do
        sleep 5
        show_header
        show_stats
        show_logs
        
        # Mostrar timestamp
        echo -e "${YELLOW}Última actualización: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo -e "Presiona Ctrl+C para salir\n"
    done
}

# Ejecutar
main
