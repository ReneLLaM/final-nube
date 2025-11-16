#!/bin/bash

################################################################################
# SCRIPT DE AUTOESCALADO PARA FRONTEND
# Monitorea recursos y escala automáticamente los contenedores frontend
# Uso: ./autoscale-frontend.sh [--debug] [--status] [--config]
################################################################################

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/autoscale.conf"
LOG_FILE="${SCRIPT_DIR}/logs/autoscale-frontend.log"
LOCK_FILE="/tmp/autoscale-frontend.lock"

# Crear directorio de logs si no existe
mkdir -p "${SCRIPT_DIR}/logs"

# Cargar configuración
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Archivo de configuración no encontrado: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Variables de control
DEBUG=${1:-""}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Configuración específica para frontend (menos agresiva)
FRONTEND_CPU_THRESHOLD=70
FRONTEND_MAX_REPLICAS=3
FRONTEND_MIN_REPLICAS=1

################################################################################
# FUNCIONES
################################################################################

# Función de logging
log() {
    local level=$1
    shift
    local message="$@"
    echo "[${TIMESTAMP}] [${level}] ${message}" >> "$LOG_FILE"
    if [ "$DEBUG" == "--debug" ]; then
        echo "[${level}] ${message}"
    fi
}

# Obtener métrica de CPU del frontend
get_frontend_cpu_usage() {
    local cpu=$(docker stats --no-stream --filter "name=chat_frontend" \
                 --format "{{.CPUPerc}}" 2>/dev/null | \
                 grep -oP '\d+\.\d+' | \
                 awk '{sum+=$1} END {print int(sum/NR)}')
    echo ${cpu:-0}
}

# Obtener métrica de Memoria del frontend
get_frontend_memory_usage() {
    local memory=$(docker stats --no-stream --filter "name=chat_frontend" \
                   --format "{{.MemPerc}}" 2>/dev/null | \
                   grep -oP '\d+\.\d+' | \
                   awk '{sum+=$1} END {print int(sum/NR)}')
    echo ${memory:-0}
}

# Contar frontends activos
count_frontends() {
    docker ps --filter "name=chat_frontend" --filter "status=running" \
              --format "{{.Names}}" 2>/dev/null | wc -l
}

# Obtener lista de frontends
get_frontends() {
    docker ps --filter "name=chat_frontend" --filter "status=running" \
              --format "{{.Names}}" 2>/dev/null
}

# Verificar salud del frontend
check_frontend_health() {
    local container=$1
    
    # Intentar conexión al puerto 80
    timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/80" 2>/dev/null
    return $?
}

# Escalar arriba (crear nuevo frontend)
scale_up() {
    local current_count=$(count_frontends)
    
    if [ $current_count -ge $FRONTEND_MAX_REPLICAS ]; then
        log "INFO" "Ya se alcanzó el máximo de frontends ($FRONTEND_MAX_REPLICAS)"
        return 1
    fi
    
    local new_name="chat_frontend_$(date +%s)"
    
    log "INFO" "🔼 Escalando arriba: Creando $new_name (actual: $current_count, máximo: $FRONTEND_MAX_REPLICAS)"
    
    docker run -d \
        --name "$new_name" \
        --network chat_network \
        -p $((8000 + current_count)):80 \
        --restart unless-stopped \
        --health-cmd="curl -f http://localhost:80/ || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        chat-frontend:latest 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "✅ Frontend $new_name creado exitosamente en puerto $((8000 + current_count))"
        echo "$(date +%s)" > "$LOCK_FILE"
        return 0
    else
        log "ERROR" "❌ Error al crear frontend $new_name"
        return 1
    fi
}

# Escalar abajo (eliminar frontend)
scale_down() {
    local current_count=$(count_frontends)
    
    if [ $current_count -le $FRONTEND_MIN_REPLICAS ]; then
        log "INFO" "Ya se alcanzó el mínimo de frontends ($FRONTEND_MIN_REPLICAS)"
        return 1
    fi
    
    # Obtener el frontend más antiguo (el primero)
    local container=$(get_frontends | head -1)
    
    if [ -z "$container" ]; then
        log "ERROR" "No hay frontends para eliminar"
        return 1
    fi
    
    log "INFO" "🔽 Escalando abajo: Eliminando $container (actual: $current_count, mínimo: $FRONTEND_MIN_REPLICAS)"
    
    # Detener gracefully
    docker stop "$container" 2>/dev/null
    sleep 2
    docker rm "$container" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "✅ Frontend $container eliminado exitosamente"
        echo "$(date +%s)" > "$LOCK_FILE"
        return 0
    else
        log "ERROR" "❌ Error al eliminar frontend $container"
        return 1
    fi
}

# Verificar cooldown
check_cooldown() {
    local action=$1
    local cooldown=$2
    
    if [ ! -f "$LOCK_FILE" ]; then
        return 0  # No hay cooldown
    fi
    
    local last_action=$(cat "$LOCK_FILE")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_action))
    
    if [ $elapsed -lt $cooldown ]; then
        return 1  # Cooldown activo
    fi
    
    return 0  # Cooldown expirado
}

# Mostrar estado
show_status() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           ESTADO DEL AUTOESCALADO - FRONTEND               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local cpu=$(get_frontend_cpu_usage)
    local memory=$(get_frontend_memory_usage)
    local count=$(count_frontends)
    
    echo "📊 MÉTRICAS:"
    echo "   CPU:       $cpu%"
    echo "   Memoria:   $memory%"
    echo "   Frontends: $count (Min: $FRONTEND_MIN_REPLICAS, Max: $FRONTEND_MAX_REPLICAS)"
    echo ""
    
    echo "🔧 CONFIGURACIÓN:"
    echo "   CPU Threshold:       $FRONTEND_CPU_THRESHOLD%"
    echo "   Scale Up Cooldown:   ${SCALE_UP_COOLDOWN}s"
    echo "   Scale Down Cooldown: ${SCALE_DOWN_COOLDOWN}s"
    echo ""
    
    echo "📦 FRONTENDS ACTIVOS:"
    get_frontends | while read frontend; do
        local status=$(docker inspect "$frontend" --format='{{.State.Status}}' 2>/dev/null)
        local port=$(docker port "$frontend" 2>/dev/null | grep -oP ':\K\d+' | head -1)
        echo "   ✓ $frontend ($status) - Puerto: $port"
    done
    
    echo ""
    echo "📝 ÚLTIMAS ACCIONES:"
    tail -5 "$LOG_FILE" 2>/dev/null || echo "   Sin registros"
    echo ""
}

# Mostrar configuración
show_config() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        CONFIGURACIÓN DE AUTOESCALADO - FRONTEND            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Configuración Global:"
    cat "$CONFIG_FILE"
    echo ""
    echo "Configuración Específica Frontend:"
    echo "   FRONTEND_CPU_THRESHOLD:  $FRONTEND_CPU_THRESHOLD%"
    echo "   FRONTEND_MAX_REPLICAS:   $FRONTEND_MAX_REPLICAS"
    echo "   FRONTEND_MIN_REPLICAS:   $FRONTEND_MIN_REPLICAS"
    echo ""
}

################################################################################
# LÓGICA PRINCIPAL
################################################################################

main() {
    # Procesar argumentos
    case "$1" in
        --status)
            show_status
            exit 0
            ;;
        --config)
            show_config
            exit 0
            ;;
        --debug)
            DEBUG="--debug"
            ;;
    esac
    
    # Obtener métricas
    local cpu=$(get_frontend_cpu_usage)
    local memory=$(get_frontend_memory_usage)
    local current_count=$(count_frontends)
    
    log "INFO" "Verificación de autoescalado | CPU: ${cpu}% | Mem: ${memory}% | Frontends: $current_count"
    
    # LÓGICA DE ESCALADO ARRIBA (menos agresiva que backend)
    if [ $cpu -gt $FRONTEND_CPU_THRESHOLD ] || [ $memory -gt 85 ]; then
        if check_cooldown "scale_up" $SCALE_UP_COOLDOWN; then
            log "WARN" "⚠️  Recursos altos detectados (CPU: ${cpu}%, Mem: ${memory}%)"
            scale_up
        else
            log "INFO" "⏳ Scale up en cooldown"
        fi
    fi
    
    # LÓGICA DE ESCALADO ABAJO (menos agresiva que backend)
    if [ $cpu -lt 20 ] && [ $memory -lt 30 ]; then
        if check_cooldown "scale_down" $SCALE_DOWN_COOLDOWN; then
            log "INFO" "📉 Recursos bajos detectados (CPU: ${cpu}%, Mem: ${memory}%)"
            scale_down
        else
            log "INFO" "⏳ Scale down en cooldown"
        fi
    fi
    
    # Verificar salud del frontend
    log "INFO" "Verificando salud del frontend..."
    get_frontends | while read frontend; do
        if ! check_frontend_health "$frontend"; then
            log "WARN" "⚠️  Frontend $frontend no responde"
        fi
    done
}

# Ejecutar
main "$@"

exit 0
