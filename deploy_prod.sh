#!/bin/bash
set -e

# Despliegue de producción para Chat en Tiempo Real

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

COMPOSE_FILE="docker-compose.prod.yml"

if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "ERROR: No se encontró docker compose. Instala Docker y docker compose."
  exit 1
fi

# Cargar configuración de autoscale si existe (para usar MIN_REPLICAS como base)
BACKEND_REPLICAS=1
FRONTEND_REPLICAS=1

if [ -f "config/autoscale.conf" ]; then
  # shellcheck disable=SC1091
  source "config/autoscale.conf"
  if [ -n "$MIN_REPLICAS" ]; then
    BACKEND_REPLICAS="$MIN_REPLICAS"
    FRONTEND_REPLICAS="$MIN_REPLICAS"
  fi
fi

echo "Construyendo imágenes de producción..."
$DOCKER_COMPOSE -f "$COMPOSE_FILE" build

echo "Levantando stack en modo producción (backend=$BACKEND_REPLICAS, frontend=$FRONTEND_REPLICAS)..."
$DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d \
  --remove-orphans \
  --scale backend="$BACKEND_REPLICAS" \
  --scale frontend="$FRONTEND_REPLICAS"

echo "Despliegue completado. Nginx escuchando en el puerto 80."
