#!/bin/bash

################################################################################
# SCRIPT DE INSTALACIÓN PARA UBUNTU
# Instala Docker, Docker Compose y configura todo para despliegue
# Uso: sudo bash install-ubuntu.sh
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="chat-app"
PROJECT_USER="${SUDO_USER:-$USER}"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   INSTALACIÓN AUTOMÁTICA - CHAT EN TIEMPO REAL             ║"
echo "║   Sistema: Ubuntu                                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

################################################################################
# FUNCIONES
################################################################################

print_step() {
    echo ""
    echo "▶️  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1"
    exit 1
}

################################################################################
# VERIFICACIONES PREVIAS
################################################################################

print_step "Verificando requisitos previos"

if [ "$EUID" -ne 0 ]; then 
    print_error "Este script debe ejecutarse con sudo"
fi

if ! command -v curl &> /dev/null; then
    print_step "Instalando curl"
    apt update
    apt install -y curl
fi

print_success "Requisitos verificados"

################################################################################
# INSTALAR DOCKER
################################################################################

print_step "Instalando Docker"

if command -v docker &> /dev/null; then
    print_success "Docker ya está instalado: $(docker --version)"
else
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    print_success "Docker instalado correctamente"
fi

################################################################################
# INSTALAR DOCKER COMPOSE
################################################################################

print_step "Instalando Docker Compose"

if command -v docker-compose &> /dev/null; then
    print_success "Docker Compose ya está instalado: $(docker-compose --version)"
else
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose instalado: $(docker-compose --version)"
fi

################################################################################
# CONFIGURAR USUARIO DOCKER
################################################################################

print_step "Configurando usuario Docker"

if id -nG "$PROJECT_USER" | grep -qw "docker"; then
    print_success "Usuario $PROJECT_USER ya está en el grupo docker"
else
    usermod -aG docker "$PROJECT_USER"
    print_success "Usuario $PROJECT_USER agregado al grupo docker"
    echo "⚠️  IMPORTANTE: El usuario debe cerrar sesión y volver a conectarse"
fi

################################################################################
# DAR PERMISOS A SCRIPTS
################################################################################

print_step "Configurando permisos de scripts"

chmod +x "$SCRIPT_DIR/scripts"/*.sh
print_success "Permisos configurados"

################################################################################
# CREAR DIRECTORIOS NECESARIOS
################################################################################

print_step "Creando directorios"

mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/backups"
mkdir -p "$SCRIPT_DIR/nginx/ssl"

chown -R "$PROJECT_USER:$PROJECT_USER" "$SCRIPT_DIR/logs"
chown -R "$PROJECT_USER:$PROJECT_USER" "$SCRIPT_DIR/backups"

print_success "Directorios creados"

################################################################################
# CONSTRUIR IMÁGENES DOCKER
################################################################################

print_step "Construyendo imágenes Docker"

cd "$SCRIPT_DIR"
docker-compose -f docker-compose.prod.yml build

print_success "Imágenes construidas"

################################################################################
# INICIAR SERVICIOS
################################################################################

print_step "Iniciando servicios"

docker-compose -f docker-compose.prod.yml up -d

# Esperar a que los servicios estén listos
echo "⏳ Esperando a que los servicios estén listos..."
sleep 10

print_success "Servicios iniciados"

################################################################################
# VERIFICAR ESTADO
################################################################################

print_step "Verificando estado de servicios"

echo ""
docker-compose ps
echo ""

# Verificar acceso
if curl -s http://localhost > /dev/null; then
    print_success "✓ Frontend accesible en http://localhost"
else
    echo "⚠️  Frontend no responde aún, espera unos segundos"
fi

if curl -s http://localhost/api/health > /dev/null; then
    print_success "✓ Backend accesible en http://localhost/api/health"
else
    echo "⚠️  Backend no responde aún, espera unos segundos"
fi

################################################################################
# CONFIGURAR CRONTAB
################################################################################

print_step "Configurando crontab para autoescalado"

CRON_FILE="/etc/cron.d/chat-autoscale"
PROJECT_PATH="$SCRIPT_DIR"

cat > "$CRON_FILE" << EOF
# Autoescalado para Chat en Tiempo Real
# Creado automáticamente por install-ubuntu.sh

# Autoescalado de backend cada 2 minutos
*/2 * * * * $PROJECT_USER $PROJECT_PATH/scripts/autoscale-backend.sh >> $PROJECT_PATH/logs/autoscale-backend.log 2>&1

# Autoescalado de frontend cada 5 minutos
*/5 * * * * $PROJECT_USER $PROJECT_PATH/scripts/autoscale-frontend.sh >> $PROJECT_PATH/logs/autoscale-frontend.log 2>&1

# Backup de BD cada 6 horas
0 */6 * * * $PROJECT_USER $PROJECT_PATH/scripts/backup.sh >> $PROJECT_PATH/logs/backup.log 2>&1

# Limpieza de logs diaria a las 2 AM
0 2 * * * $PROJECT_USER $PROJECT_PATH/scripts/cleanup.sh >> $PROJECT_PATH/logs/cleanup.log 2>&1

# Verificación de salud cada 5 minutos
*/5 * * * * $PROJECT_USER curl -s http://localhost/health > /dev/null 2>&1 || echo "Health check failed" >> $PROJECT_PATH/logs/health.log
EOF

chmod 644 "$CRON_FILE"
print_success "Crontab configurado en $CRON_FILE"

################################################################################
# RESUMEN FINAL
################################################################################

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ✅ INSTALACIÓN COMPLETADA                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "📋 INFORMACIÓN IMPORTANTE:"
echo ""
echo "1. 🌐 ACCESO A LA APLICACIÓN:"
echo "   • Frontend: http://localhost"
echo "   • Backend API: http://localhost/api/health"
echo "   • Nginx: http://localhost"
echo ""

echo "2. 📊 MONITOREO:"
echo "   • Ver estado: docker-compose ps"
echo "   • Ver logs: docker-compose logs -f"
echo "   • Ver autoescalado: tail -f $PROJECT_PATH/logs/autoscale-backend.log"
echo ""

echo "3. ⚙️  CONFIGURACIÓN:"
echo "   • Editar config: nano $PROJECT_PATH/config/autoscale.conf"
echo "   • Editar .env: nano $PROJECT_PATH/.env"
echo "   • Ver crontab: sudo crontab -l"
echo ""

echo "4. 🔧 COMANDOS ÚTILES:"
echo "   • Ver backends: docker ps --filter 'name=chat_backend'"
echo "   • Ver estado autoescalado: bash $PROJECT_PATH/scripts/autoscale-backend.sh --status"
echo "   • Ver config autoescalado: bash $PROJECT_PATH/scripts/autoscale-backend.sh --config"
echo ""

echo "5. ⚠️  PRÓXIMOS PASOS:"
echo "   • Cambiar contraseña de BD en .env"
echo "   • Configurar SSL/TLS para producción"
echo "   • Realizar pruebas de carga"
echo "   • Configurar monitoreo (CloudWatch, Datadog, etc)"
echo ""

echo "📚 DOCUMENTACIÓN:"
echo "   • Guía completa: $PROJECT_PATH/DEPLOYMENT_UBUNTU.md"
echo "   • README: $PROJECT_PATH/README.md"
echo ""

echo "✨ ¡Tu aplicación está lista para producción!"
echo ""
