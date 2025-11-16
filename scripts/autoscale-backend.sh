#!/bin/bash

################################################################################
# SCRIPT DE AUTOESCALADO PARA BACKEND
# Monitorea recursos y escala automáticamente los contenedores backend
# Uso: ./autoscale-backend.sh [--debug] [--status] [--config]
################################################################################

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/autoscale.conf"
LOG_FILE="${SCRIPT_DIR}/logs/autoscale-backend.log"
LOCK_FILE="/tmp/autoscale-backend.lock"

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

# Obtener métrica de CPU
get_cpu_usage() {
    local cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" 2>/dev/null | \
                 grep -oP '\d+\.\d+' | \
                 awk '{sum+=$1} END {print int(sum/NR)}')
    echo ${cpu:-0}
}

# Obtener métrica de Memoria
get_memory_usage() {
    local memory=$(docker stats --no-stream --format "{{.MemPerc}}" 2>/dev/null | \
                   grep -oP '\d+\.\d+' | \
                   awk '{sum+=$1} END {print int(sum/NR)}')
    echo ${memory:-0}
}

# Contar backends activos
count_backends() {
    docker ps --filter "name=chat_backend" --filter "status=running" \
              --format "{{.Names}}" 2>/dev/null | wc -l
}

# Obtener lista de backends
get_backends() {
    docker ps --filter "name=chat_backend" --filter "status=running" \
              --format "{{.Names}}" 2>/dev/null
}

# Verificar salud de un backend
check_backend_health() {
    local container=$1
    local port=$(docker inspect "$container" --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}{{end}}' 2>/dev/null | grep -oP '\d+' | head -1)
    
    if [ -z "$port" ]; then
        port=3000
    fi
    
    # Intentar conexión
    timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/$port" 2>/dev/null
    return $?
}

# Escalar arriba (crear nuevo backend)
scale_up() {
    local current_count=$(count_backends)
    
    if [ $current_count -ge $MAX_REPLICAS ]; then
        log "INFO" "Ya se alcanzó el máximo de réplicas ($MAX_REPLICAS)"
        return 1
    fi
    
    local new_name="chat_backend_$(date +%s)"
    
    log "INFO" "🔼 Escalando arriba: Creando $new_name (actual: $current_count, máximo: $MAX_REPLICAS)"
    
    docker run -d \
        --name "$new_name" \
        --network chat_network \
        -e NODE_ENV=production \
        -e DB_HOST=db \
        -e DB_PORT=5432 \
        -e DB_USER=chatuser \
        -e DB_PASSWORD=chatpass123 \
        -e DB_NAME=chatdb \
        -e PORT=3000 \
        --restart unless-stopped \
        --health-cmd="curl -f http://localhost:3000/health || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        chat-backend:latest 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "✅ Backend $new_name creado exitosamente"
        echo "$(date +%s)" > "$LOCK_FILE"
        return 0
    else
        log "ERROR" "❌ Error al crear backend $new_name"
        return 1
    fi
}

# Escalar abajo (eliminar backend)
scale_down() {
    local current_count=$(count_backends)
    
    if [ $current_count -le $MIN_REPLICAS ]; then
        log "INFO" "Ya se alcanzó el mínimo de réplicas ($MIN_REPLICAS)"
        return 1
    fi
    
    # Obtener el backend más antiguo (el primero)
    local container=$(get_backends | head -1)
    
    if [ -z "$container" ]; then
        log "ERROR" "No hay backends para eliminar"
        return 1
    fi
    
    log "INFO" "🔽 Escalando abajo: Eliminando $container (actual: $current_count, mínimo: $MIN_REPLICAS)"
    
    # Detener gracefully
    docker stop "$container" 2>/dev/null
    sleep 2
    docker rm "$container" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "✅ Backend $container eliminado exitosamente"
        echo "$(date +%s)" > "$LOCK_FILE"
        return 0
    else
        log "ERROR" "❌ Error al eliminar backend $container"
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
    echo "║           ESTADO DEL AUTOESCALADO - BACKEND                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local cpu=$(get_cpu_usage)
    local memory=$(get_memory_usage)
    local count=$(count_backends)
    
    echo "📊 MÉTRICAS:"
    echo "   CPU:       $cpu%"
    echo "   Memoria:   $memory%"
    echo "   Backends:  $count (Min: $MIN_REPLICAS, Max: $MAX_REPLICAS)"
    echo ""
    
    echo "🔧 CONFIGURACIÓN:"
    echo "   CPU Threshold:       $CPU_THRESHOLD%"
    echo "   Scale Up Cooldown:   ${SCALE_UP_COOLDOWN}s"
    echo "   Scale Down Cooldown: ${SCALE_DOWN_COOLDOWN}s"
    echo ""
    
    echo "📦 BACKENDS ACTIVOS:"
    get_backends | while read backend; do
        local status=$(docker inspect "$backend" --format='{{.State.Status}}' 2>/dev/null)
        echo "   ✓ $backend ($status)"
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
    echo "║        CONFIGURACIÓN DE AUTOESCALADO - BACKEND             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    cat "$CONFIG_FILE"
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
    local cpu=$(get_cpu_usage)
    local memory=$(get_memory_usage)
    local current_count=$(count_backends)
    
    log "INFO" "Verificación de autoescalado | CPU: ${cpu}% | Mem: ${memory}% | Backends: $current_count"
    
    # LÓGICA DE ESCALADO ARRIBA
    if [ $cpu -gt $CPU_THRESHOLD ] || [ $memory -gt 80 ]; then
        if check_cooldown "scale_up" $SCALE_UP_COOLDOWN; then
            log "WARN" "⚠️  Recursos altos detectados (CPU: ${cpu}%, Mem: ${memory}%)"
            scale_up
        else
            log "INFO" "⏳ Scale up en cooldown"
        fi
    fi
    
    # LÓGICA DE ESCALADO ABAJO
    if [ $cpu -lt 30 ] && [ $memory -lt 40 ]; then
        if check_cooldown "scale_down" $SCALE_DOWN_COOLDOWN; then
            log "INFO" "📉 Recursos bajos detectados (CPU: ${cpu}%, Mem: ${memory}%)"
            scale_down
        else
            log "INFO" "⏳ Scale down en cooldown"
        fi
    fi
    
    # Verificar salud de backends
    log "INFO" "Verificando salud de backends..."
    get_backends | while read backend; do
        if ! check_backend_health "$backend"; then
            log "WARN" "⚠️  Backend $backend no responde"
        fi
    done
}

# Ejecutar
main "$@"

exit 0
