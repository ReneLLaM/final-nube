#!/bin/bash

################################################################################
# Script de Inicio Rápido - Chat en Tiempo Real
# Inicia la aplicación completa con un solo comando
# Uso: ./start.sh
################################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Chat en Tiempo Real - Script de Inicio Rápido          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar Docker
echo -e "${YELLOW}Verificando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker no está instalado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker encontrado${NC}"

# Verificar Docker Compose
echo -e "${YELLOW}Verificando Docker Compose...${NC}"
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ Docker Compose no está instalado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose encontrado${NC}"

# Crear directorios necesarios
echo -e "${YELLOW}Creando directorios...${NC}"
mkdir -p "${PROJECT_DIR}/logs"
mkdir -p "${PROJECT_DIR}/backups"
mkdir -p "${PROJECT_DIR}/config"
mkdir -p "${PROJECT_DIR}/nginx/ssl"
echo -e "${GREEN}✓ Directorios creados${NC}"

# Generar certificados SSL autofirmados si no existen
if [ ! -f "${PROJECT_DIR}/nginx/ssl/cert.pem" ]; then
    echo -e "${YELLOW}Generando certificados SSL autofirmados...${NC}"
    openssl req -x509 -newkey rsa:4096 -keyout "${PROJECT_DIR}/nginx/ssl/key.pem" \
        -out "${PROJECT_DIR}/nginx/ssl/cert.pem" -days 365 -nodes \
        -subj "/C=ES/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null || true
    echo -e "${GREEN}✓ Certificados generados${NC}"
fi

# Detener contenedores previos si existen
echo -e "${YELLOW}Limpiando contenedores previos...${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✓ Contenedores limpios${NC}"

# Construir imágenes
echo -e "${YELLOW}Construyendo imágenes Docker...${NC}"
docker-compose build --no-cache
echo -e "${GREEN}✓ Imágenes construidas${NC}"

# Iniciar servicios
echo -e "${YELLOW}Iniciando servicios...${NC}"
docker-compose up -d
echo -e "${GREEN}✓ Servicios iniciados${NC}"

# Esperar a que la BD esté lista
echo -e "${YELLOW}Esperando a que la base de datos esté lista...${NC}"
for i in {1..30}; do
    if docker-compose exec -T db pg_isready -U chatuser > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Base de datos lista${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Esperar a que el backend esté listo
echo -e "${YELLOW}Esperando a que el backend esté listo...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Backend listo${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Mostrar información
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              ✓ Aplicación iniciada exitosamente           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}URLs de acceso:${NC}"
echo -e "  Frontend:     ${YELLOW}http://localhost${NC}"
echo -e "  Backend API:  ${YELLOW}http://localhost:3000/api/health${NC}"
echo -e "  Nginx:        ${YELLOW}http://localhost:80${NC}"
echo ""

echo -e "${GREEN}Comandos útiles:${NC}"
echo -e "  Ver logs:           ${YELLOW}docker-compose logs -f${NC}"
echo -e "  Ver estado:         ${YELLOW}docker-compose ps${NC}"
echo -e "  Detener:            ${YELLOW}docker-compose down${NC}"
echo -e "  Autoescalabilidad:  ${YELLOW}./scripts/autoscale.sh --status${NC}"
echo ""

echo -e "${YELLOW}Configurar crontab (Linux):${NC}"
echo -e "  ${YELLOW}./scripts/setup-crontab.sh${NC}"
echo ""

echo -e "${GREEN}✓ ¡Listo para usar!${NC}"
echo ""

# Mostrar estado de contenedores
echo -e "${BLUE}Estado de contenedores:${NC}"
docker-compose ps

echo ""
echo -e "${YELLOW}Presiona Ctrl+C para ver los logs en tiempo real${NC}"
docker-compose logs -f
