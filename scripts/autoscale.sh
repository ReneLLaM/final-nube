#!/bin/bash

################################################################################
# Script de Autoescalabilidad para Chat en Tiempo Real
# Monitorea recursos y escala contenedores automáticamente
# Uso: ./autoscale.sh
################################################################################

set -e

# Configuración
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${PROJECT_DIR}/logs/autoscale.log"
METRICS_FILE="${PROJECT_DIR}/logs/metrics.json"
CONFIG_FILE="${PROJECT_DIR}/config/autoscale.conf"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Crear directorio de logs si no existe
mkdir -p "${PROJECT_DIR}/logs"
mkdir -p "${PROJECT_DIR}/config"

# Valores por defecto (pueden ser sobrescritos por config file)
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
MIN_REPLICAS=1
MAX_REPLICAS=5
SCALE_UP_COOLDOWN=300
SCALE_DOWN_COOLDOWN=600
HEALTH_CHECK_INTERVAL=60

# Cargar configuración personalizada si existe
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

################################################################################
# Funciones de Logging
################################################################################

log() {
    echo "[${TIMESTAMP}] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[${TIMESTAMP}] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_info() {
    echo "[${TIMESTAMP}] INFO: $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[${TIMESTAMP}] WARNING: $1" | tee -a "$LOG_FILE"
}

################################################################################
# Funciones de Monitoreo
################################################################################

# Obtener uso de CPU del contenedor backend
get_cpu_usage() {
    local container_name="chat_backend"
    
    if ! docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        log_error "Contenedor $container_name no encontrado"
        return 1
    fi

    # Obtener estadísticas de Docker
    local stats=$(docker stats "$container_name" --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//g')
    
    if [ -z "$stats" ]; then
        log_warning "No se pudo obtener estadísticas de CPU"
        return 1
    fi

    echo "$stats"
}

# Obtener uso de memoria del contenedor backend
get_memory_usage() {
    local container_name="chat_backend"
    
    if ! docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
        log_error "Contenedor $container_name no encontrado"
        return 1
    fi

    # Obtener estadísticas de Docker
    local stats=$(docker stats "$container_name" --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//g')
    
    if [ -z "$stats" ]; then
        log_warning "No se pudo obtener estadísticas de memoria"
        return 1
    fi

    echo "$stats"
}

# Obtener número de conexiones activas
get_active_connections() {
    local db_container="chat_db"
    
    if ! docker ps --filter "name=$db_container" --format "{{.Names}}" | grep -q "$db_container"; then
        log_error "Contenedor $db_container no encontrado"
        return 1
    fi

    # Consultar base de datos para conexiones activas
    local count=$(docker exec "$db_container" psql -U chatuser -d chatdb -t -c \
        "SELECT COUNT(*) FROM active_connections WHERE disconnected_at IS NULL" 2>/dev/null || echo "0")
    
    echo "$count"
}

# Obtener número de mensajes por minuto
get_messages_per_minute() {
    local db_container="chat_db"
    
    if ! docker ps --filter "name=$db_container" --format "{{.Names}}" | grep -q "$db_container"; then
        return 1
    fi

    # Contar mensajes del último minuto
    local count=$(docker exec "$db_container" psql -U chatuser -d chatdb -t -c \
        "SELECT COUNT(*) FROM messages WHERE created_at > NOW() - INTERVAL '1 minute'" 2>/dev/null || echo "0")
    
    echo "$count"
}

# Verificar salud del backend
check_backend_health() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# Verificar salud del frontend
check_frontend_health() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# Verificar salud de la base de datos
check_database_health() {
    local db_container="chat_db"
    
    if ! docker ps --filter "name=$db_container" --format "{{.Names}}" | grep -q "$db_container"; then
        return 1
    fi

    docker exec "$db_container" pg_isready -U chatuser > /dev/null 2>&1
    return $?
}

################################################################################
# Funciones de Escalado
################################################################################

# Escalar backend hacia arriba
scale_up_backend() {
    log_info "Escalando backend hacia arriba..."
    
    # Crear un nuevo contenedor backend
    local new_container_name="chat_backend_$(date +%s)"
    
    docker run -d \
        --name "$new_container_name" \
        --network chat_network \
        -e NODE_ENV=production \
        -e DB_HOST=db \
        -e DB_PORT=5432 \
        -e DB_USER=chatuser \
        -e DB_PASSWORD=chatpass123 \
        -e DB_NAME=chatdb \
        -e PORT=3000 \
        --restart unless-stopped \
        chat-backend:latest > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Nuevo contenedor backend creado: $new_container_name"
        return 0
    else
        log_error "Error al crear nuevo contenedor backend"
        return 1
    fi
}

# Escalar backend hacia abajo
scale_down_backend() {
    log_info "Escalando backend hacia abajo..."
    
    # Obtener contenedores backend adicionales (no el principal)
    local containers=$(docker ps --filter "name=chat_backend_" --format "{{.Names}}" | head -1)
    
    if [ -z "$containers" ]; then
        log_warning "No hay contenedores adicionales para escalar hacia abajo"
        return 1
    fi

    docker stop "$containers" > /dev/null 2>&1
    docker rm "$containers" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Contenedor backend eliminado: $containers"
        return 0
    else
        log_error "Error al eliminar contenedor backend"
        return 1
    fi
}

# Reiniciar contenedor si está fallando
restart_container() {
    local container_name=$1
    
    log_warning "Reiniciando contenedor: $container_name"
    docker restart "$container_name" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_info "Contenedor reiniciado exitosamente: $container_name"
        return 0
    else
        log_error "Error al reiniciar contenedor: $container_name"
        return 1
    fi
}

################################################################################
# Funciones de Métricas
################################################################################

# Guardar métricas en JSON
save_metrics() {
    local cpu=$1
    local memory=$2
    local connections=$3
    local mpm=$4
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$METRICS_FILE" <<EOF
{
  "timestamp": "$timestamp",
  "cpu_usage": $cpu,
  "memory_usage": $memory,
  "active_connections": $connections,
  "messages_per_minute": $mpm,
  "backend_status": "$(check_backend_health && echo 'healthy' || echo 'unhealthy')",
  "frontend_status": "$(check_frontend_health && echo 'healthy' || echo 'unhealthy')",
  "database_status": "$(check_database_health && echo 'healthy' || echo 'unhealthy')"
}
EOF
}

# Mostrar métricas
show_metrics() {
    if [ -f "$METRICS_FILE" ]; then
        log_info "Métricas actuales:"
        cat "$METRICS_FILE" | jq '.' 2>/dev/null || cat "$METRICS_FILE"
    fi
}

################################################################################
# Función Principal de Monitoreo
################################################################################

monitor_and_scale() {
    log_info "=== Iniciando ciclo de monitoreo y escalado ==="

    # Obtener métricas
    local cpu=$(get_cpu_usage || echo "0")
    local memory=$(get_memory_usage || echo "0")
    local connections=$(get_active_connections || echo "0")
    local mpm=$(get_messages_per_minute || echo "0")

    log_info "CPU: ${cpu}% | Memoria: ${memory}% | Conexiones: $connections | Mensajes/min: $mpm"

    # Guardar métricas
    save_metrics "$cpu" "$memory" "$connections" "$mpm"

    # Verificar salud de servicios
    if ! check_backend_health; then
        log_warning "Backend no responde, intentando reiniciar..."
        restart_container "chat_backend"
    fi

    if ! check_frontend_health; then
        log_warning "Frontend no responde, intentando reiniciar..."
        restart_container "chat_frontend"
    fi

    if ! check_database_health; then
        log_error "Base de datos no responde"
        restart_container "chat_db"
    fi

    # Lógica de escalado automático
    if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )) || (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )); then
        log_warning "Recursos altos detectados (CPU: ${cpu}%, Memoria: ${memory}%)"
        
        # Verificar cooldown de scale up
        if [ ! -f "${PROJECT_DIR}/.scale_up_cooldown" ] || [ $(( $(date +%s) - $(stat -f%m "${PROJECT_DIR}/.scale_up_cooldown" 2>/dev/null || echo 0) )) -gt $SCALE_UP_COOLDOWN ]; then
            scale_up_backend
            touch "${PROJECT_DIR}/.scale_up_cooldown"
        else
            log_info "Scale up en cooldown"
        fi
    elif (( $(echo "$cpu < 30" | bc -l) )) && (( $(echo "$memory < 40" | bc -l) )); then
        log_info "Recursos bajos detectados, considerando scale down"
        
        # Verificar cooldown de scale down
        if [ ! -f "${PROJECT_DIR}/.scale_down_cooldown" ] || [ $(( $(date +%s) - $(stat -f%m "${PROJECT_DIR}/.scale_down_cooldown" 2>/dev/null || echo 0) )) -gt $SCALE_DOWN_COOLDOWN ]; then
            scale_down_backend
            touch "${PROJECT_DIR}/.scale_down_cooldown"
        else
            log_info "Scale down en cooldown"
        fi
    fi

    log_info "=== Ciclo de monitoreo completado ==="
}

################################################################################
# Funciones de Utilidad
################################################################################

# Mostrar ayuda
show_help() {
    cat <<EOF
Uso: $0 [OPCIÓN]

Opciones:
  -m, --monitor       Ejecutar monitoreo una sola vez
  -d, --daemon        Ejecutar como daemon (requiere crontab)
  -s, --status        Mostrar estado actual de métricas
  -c, --config        Mostrar configuración actual
  -h, --help          Mostrar esta ayuda

Ejemplos:
  $0 --monitor        # Ejecutar monitoreo una sola vez
  $0 --status         # Ver métricas actuales
  $0 --config         # Ver configuración

Para ejecutar automáticamente cada minuto, añade a crontab:
  * * * * * $0 --monitor >> ${LOG_FILE} 2>&1

Para ejecutar cada 5 minutos:
  */5 * * * * $0 --monitor >> ${LOG_FILE} 2>&1

EOF
}

# Mostrar configuración
show_config() {
    cat <<EOF
=== Configuración de Autoescalabilidad ===
CPU Threshold: ${CPU_THRESHOLD}%
Memory Threshold: ${MEMORY_THRESHOLD}%
Min Replicas: ${MIN_REPLICAS}
Max Replicas: ${MAX_REPLICAS}
Scale Up Cooldown: ${SCALE_UP_COOLDOWN}s
Scale Down Cooldown: ${SCALE_DOWN_COOLDOWN}s
Health Check Interval: ${HEALTH_CHECK_INTERVAL}s
Project Directory: ${PROJECT_DIR}
Log File: ${LOG_FILE}
Metrics File: ${METRICS_FILE}
EOF
}

################################################################################
# Main
################################################################################

# Procesar argumentos
case "${1:-}" in
    -m|--monitor)
        monitor_and_scale
        ;;
    -d|--daemon)
        log_info "Ejecutando en modo daemon"
        while true; do
            monitor_and_scale
            sleep "$HEALTH_CHECK_INTERVAL"
        done
        ;;
    -s|--status)
        show_metrics
        ;;
    -c|--config)
        show_config
        ;;
    -h|--help|"")
        show_help
        ;;
    *)
        log_error "Opción desconocida: $1"
        show_help
        exit 1
        ;;
esac

exit 0
