#!/bin/bash
set -e

# Autoescalado sencillo basado en CPU usando docker compose scale

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

COMPOSE_FILE="docker-compose.prod.yml"

if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "ERROR: No se encontró docker compose."
  exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: No se encontró $COMPOSE_FILE. Ejecuta este script en la raíz del proyecto."
  exit 1
fi

if [ ! -f "config/autoscale.conf" ]; then
  echo "ERROR: No se encontró config/autoscale.conf"
  exit 1
fi

# shellcheck disable=SC1091
source "config/autoscale.conf"

MIN_REPLICAS=${MIN_REPLICAS:-1}
MAX_REPLICAS=${MAX_REPLICAS:-5}
CPU_THRESHOLD=${CPU_THRESHOLD:-50}
SCALE_UP_COOLDOWN=${SCALE_UP_COOLDOWN:-60}
SCALE_DOWN_COOLDOWN=${SCALE_DOWN_COOLDOWN:-120}

# Número actual de réplicas de backend
CURRENT_REPLICAS=$($DOCKER_COMPOSE -f "$COMPOSE_FILE" ps -q backend | wc -l | tr -d ' ')

if [ "$CURRENT_REPLICAS" -eq 0 ]; then
  echo "Backend no está corriendo, nada que escalar."
  exit 0
fi

# Calcular CPU promedio de los contenedores de backend
CONTAINERS=$($DOCKER_COMPOSE -f "$COMPOSE_FILE" ps -q backend)
if [ -z "$CONTAINERS" ]; then
  echo "No se encontraron contenedores de backend."
  exit 0
fi

CPU_AVG=$(docker stats --no-stream --format "{{.CPUPerc}}" $CONTAINERS | \
  sed 's/%//' | awk '{sum+=$1; n+=1} END { if (n>0) print sum/n; else print 0 }')

CPU_INT=$(printf '%.0f' "$CPU_AVG")

NOW=$(date +%s)
STATE_DIR="/tmp/chat_autoscale"
mkdir -p "$STATE_DIR"
LAST_UP_FILE="$STATE_DIR/last_scale_up"
LAST_DOWN_FILE="$STATE_DIR/last_scale_down"

LAST_UP=0
LAST_DOWN=0
[ -f "$LAST_UP_FILE" ] && LAST_UP=$(cat "$LAST_UP_FILE")
[ -f "$LAST_DOWN_FILE" ] && LAST_DOWN=$(cat "$LAST_DOWN_FILE")

CAN_SCALE_UP=0
CAN_SCALE_DOWN=0

if [ $((NOW - LAST_UP)) -ge "$SCALE_UP_COOLDOWN" ]; then
  CAN_SCALE_UP=1
fi

if [ $((NOW - LAST_DOWN)) -ge "$SCALE_DOWN_COOLDOWN" ]; then
  CAN_SCALE_DOWN=1
fi

TARGET_REPLICAS="$CURRENT_REPLICAS"
CHANGED=0

# Regla simple: escalar hacia arriba si CPU > UMBRAL
if [ "$CPU_INT" -gt "$CPU_THRESHOLD" ] && [ "$CURRENT_REPLICAS" -lt "$MAX_REPLICAS" ] && [ "$CAN_SCALE_UP" -eq 1 ]; then
  TARGET_REPLICAS=$((CURRENT_REPLICAS + 1))
  echo "CPU promedio ${CPU_AVG}% > ${CPU_THRESHOLD}%. Escalando a ${TARGET_REPLICAS} réplicas."
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d \
    --scale backend="$TARGET_REPLICAS" \
    --scale frontend="$TARGET_REPLICAS"
  echo "$NOW" > "$LAST_UP_FILE"
  CHANGED=1
fi

# Regla simple: escalar hacia abajo si CPU < UMBRAL/2
LOW_THRESHOLD=$((CPU_THRESHOLD / 2))
if [ "$CHANGED" -eq 0 ] && [ "$CPU_INT" -lt "$LOW_THRESHOLD" ] && [ "$CURRENT_REPLICAS" -gt "$MIN_REPLICAS" ] && [ "$CAN_SCALE_DOWN" -eq 1 ]; then
  TARGET_REPLICAS=$((CURRENT_REPLICAS - 1))
  echo "CPU promedio ${CPU_AVG}% < ${LOW_THRESHOLD}%. Reduciendo a ${TARGET_REPLICAS} réplicas."
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d \
    --scale backend="$TARGET_REPLICAS" \
    --scale frontend="$TARGET_REPLICAS"
  echo "$NOW" > "$LAST_DOWN_FILE"
  CHANGED=1
fi

if [ "$CHANGED" -eq 0 ]; then
  echo "Sin cambios. Réplicas actuales: $CURRENT_REPLICAS, CPU promedio: ${CPU_AVG}%"
fi
