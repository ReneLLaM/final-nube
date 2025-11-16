.PHONY: help build up down logs status clean restart backup health autoscale

# Variables
PROJECT_NAME := chat-app
DOCKER_COMPOSE := docker-compose
SCRIPTS_DIR := scripts

help:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║     Chat en Tiempo Real - Comandos Disponibles            ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Comandos principales:"
	@echo "  make build        - Construir imágenes Docker"
	@echo "  make up           - Iniciar servicios"
	@echo "  make down         - Detener servicios"
	@echo "  make restart      - Reiniciar servicios"
	@echo "  make logs         - Ver logs en tiempo real"
	@echo "  make status       - Ver estado de servicios"
	@echo ""
	@echo "Mantenimiento:"
	@echo "  make clean        - Limpiar contenedores y volúmenes"
	@echo "  make backup       - Hacer backup de base de datos"
	@echo "  make health       - Verificar salud de servicios"
	@echo "  make autoscale    - Ver estado de autoescalabilidad"
	@echo ""
	@echo "Desarrollo:"
	@echo "  make shell-backend  - Acceder a shell del backend"
	@echo "  make shell-db       - Acceder a shell de la BD"
	@echo "  make ps             - Listar contenedores"
	@echo ""

build:
	@echo "Construyendo imágenes Docker..."
	$(DOCKER_COMPOSE) build --no-cache
	@echo "✓ Imágenes construidas"

up:
	@echo "Iniciando servicios..."
	$(DOCKER_COMPOSE) up -d
	@echo "✓ Servicios iniciados"
	@echo "Accede a: http://localhost"

down:
	@echo "Deteniendo servicios..."
	$(DOCKER_COMPOSE) down
	@echo "✓ Servicios detenidos"

restart:
	@echo "Reiniciando servicios..."
	$(DOCKER_COMPOSE) restart
	@echo "✓ Servicios reiniciados"

logs:
	$(DOCKER_COMPOSE) logs -f

logs-backend:
	$(DOCKER_COMPOSE) logs -f backend

logs-db:
	$(DOCKER_COMPOSE) logs -f db

logs-nginx:
	$(DOCKER_COMPOSE) logs -f nginx

status:
	@echo "Estado de servicios:"
	$(DOCKER_COMPOSE) ps

clean:
	@echo "Limpiando contenedores y volúmenes..."
	$(DOCKER_COMPOSE) down -v
	@echo "✓ Limpieza completada"

backup:
	@echo "Realizando backup..."
	@bash $(SCRIPTS_DIR)/backup.sh
	@echo "✓ Backup completado"

health:
	@echo "Verificando salud de servicios..."
	@curl -s http://localhost:3000/api/health | jq . || echo "Backend no responde"
	@curl -s http://localhost/health | jq . || echo "Nginx no responde"

autoscale:
	@bash $(SCRIPTS_DIR)/autoscale.sh --status

autoscale-config:
	@bash $(SCRIPTS_DIR)/autoscale.sh --config

autoscale-monitor:
	@bash $(SCRIPTS_DIR)/autoscale.sh --monitor

setup-crontab:
	@bash $(SCRIPTS_DIR)/setup-crontab.sh

shell-backend:
	$(DOCKER_COMPOSE) exec backend sh

shell-db:
	$(DOCKER_COMPOSE) exec db psql -U chatuser -d chatdb

shell-nginx:
	$(DOCKER_COMPOSE) exec nginx sh

ps:
	docker ps -a

images:
	docker images

volumes:
	docker volume ls

network:
	docker network ls

prune:
	@echo "Limpiando recursos de Docker..."
	docker system prune -f
	@echo "✓ Limpieza completada"

test-connection:
	@echo "Probando conexiones..."
	@echo "Backend: " && curl -s http://localhost:3000/api/health | jq .
	@echo "Frontend: " && curl -s http://localhost | head -c 100
	@echo "Database: " && docker-compose exec -T db pg_isready -U chatuser

install-deps:
	@echo "Instalando dependencias..."
	@cd backend && npm install
	@echo "✓ Dependencias instaladas"

dev:
	@echo "Iniciando en modo desarrollo..."
	$(DOCKER_COMPOSE) -f docker-compose.yml up

prod:
	@echo "Iniciando en modo producción..."
	NODE_ENV=production $(DOCKER_COMPOSE) up -d

update:
	@echo "Actualizando aplicación..."
	git pull
	$(DOCKER_COMPOSE) build --no-cache
	$(DOCKER_COMPOSE) up -d
	@echo "✓ Aplicación actualizada"

version:
	@echo "Chat en Tiempo Real v1.0.0"
	@echo "Docker: $$(docker --version)"
	@echo "Docker Compose: $$(docker-compose --version)"

.DEFAULT_GOAL := help
