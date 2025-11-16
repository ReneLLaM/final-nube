# 📦 Guía Completa: Despliegue en Ubuntu Server + Pruebas de Autoescalado

## 🎯 Objetivo
Desplegar la aplicación de chat en tiempo real en Ubuntu Server con autoescalado automático y realizar pruebas de carga.

---

## 📋 Requisitos Previos

### Hardware Mínimo
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Disco**: 20 GB
- **Conexión**: Internet estable

### Software Requerido
- Ubuntu Server 20.04 LTS o superior
- Docker 20.10+
- Docker Compose 2.0+
- Git
- curl
- htop (opcional, para monitoreo)

---

## 🚀 PASO 1: Preparar el Servidor Ubuntu

### 1.1 Conectarse al servidor
```bash
ssh usuario@ip_del_servidor
# Ejemplo: ssh ubuntu@192.168.1.100
```

### 1.2 Actualizar el sistema
```bash
sudo apt update
sudo apt upgrade -y
```

### 1.3 Instalar dependencias básicas
```bash
sudo apt install -y \
  curl \
  wget \
  git \
  htop \
  net-tools \
  build-essential
```

---

## 🐳 PASO 2: Instalar Docker y Docker Compose

### 2.1 Instalar Docker
```bash
# Descargar script de instalación oficial
curl -fsSL https://get.docker.com -o get-docker.sh

# Ejecutar instalación
sudo sh get-docker.sh

# Verificar instalación
docker --version
```

### 2.2 Instalar Docker Compose
```bash
# Descargar Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Dar permisos ejecutables
sudo chmod +x /usr/local/bin/docker-compose

# Verificar instalación
docker-compose --version
```

### 2.3 Agregar usuario al grupo docker
```bash
# Agregar usuario actual al grupo docker
sudo usermod -aG docker $USER

# Aplicar cambios (sin cerrar sesión)
newgrp docker

# Verificar (sin usar sudo)
docker ps
```

---

## 📂 PASO 3: Clonar y Configurar el Proyecto

### 3.1 Clonar el repositorio
```bash
# Ir a directorio de aplicaciones
cd /opt

# Clonar el proyecto
sudo git clone <URL_DE_TU_REPOSITORIO> chat-app

# Cambiar propietario
sudo chown -R $USER:$USER chat-app

# Entrar al directorio
cd chat-app
```

### 3.2 Verificar estructura del proyecto
```bash
ls -la
```

Deberías ver:
```
.env
.gitignore
AUTOESCALADO_EXPLICADO.md
README.md
DESPLIEGUE_UBUNTU.md
docker-compose.yml
docker-compose.prod.yml
init.sql
backend/
frontend/
nginx/
scripts/
config/
```

### 3.3 Crear directorios necesarios
```bash
# Crear directorios para logs y backups
mkdir -p logs backups

# Dar permisos
chmod -R 755 logs backups
```

---

## ⚙️ PASO 4: Configurar Variables de Entorno

### 4.1 Revisar archivo .env
```bash
cat .env
```

Contenido esperado:
```
DB_HOST=db
DB_PORT=5432
DB_USER=chatuser
DB_PASSWORD=chatpass123
DB_NAME=chatdb
NODE_ENV=production
```

### 4.2 Modificar si es necesario (OPCIONAL)
```bash
nano .env
```

**⚠️ IMPORTANTE**: En producción, cambiar `chatpass123` por una contraseña fuerte.

---

## 🏗️ PASO 5: Construir y Levantar Servicios

### 5.1 Construir imágenes Docker
```bash
# Construir todas las imágenes
docker-compose -f docker-compose.prod.yml build

# Esto puede tomar 5-10 minutos
```

### 5.2 Verificar imágenes creadas
```bash
docker images | grep chat
```

Deberías ver:
```
chat-backend          latest
chat-frontend         latest
```

### 5.3 Levantar servicios en background
```bash
# Iniciar servicios
docker-compose -f docker-compose.prod.yml up -d

# Ver estado
docker-compose -f docker-compose.prod.yml ps
```

### 5.4 Esperar a que todo esté listo
```bash
# Esperar 30 segundos para que la BD se inicialice
sleep 30

# Verificar logs
docker-compose -f docker-compose.prod.yml logs -f db
```

Deberías ver algo como:
```
db_1  | LOG:  database system is ready to accept connections
```

### 5.5 Verificar que todo está corriendo
```bash
docker-compose -f docker-compose.prod.yml ps
```

Salida esperada:
```
NAME              COMMAND                  SERVICE     STATUS      PORTS
chat_db           "docker-entrypoint.s…"   db          Up 30s      5432/tcp
chat_backend      "docker-entrypoint.s…"   backend     Up 20s      0.0.0.0:3000->3000/tcp
chat_frontend     "nginx -g daemon off…"   frontend    Up 20s      0.0.0.0:3001->80/tcp
chat_nginx        "nginx -g daemon off…"   nginx       Up 15s      0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

---

## 🔧 PASO 6: Configurar Autoescalado con Crontab

### 6.1 Hacer scripts ejecutables
```bash
chmod +x scripts/*.sh
```

### 6.2 Verificar scripts
```bash
ls -la scripts/
```

Deberías ver:
```
-rwxr-xr-x autoscale.sh
-rwxr-xr-x backup.sh
-rwxr-xr-x cleanup.sh
-rwxr-xr-x setup-crontab.sh
```

### 6.3 Configurar crontab automáticamente
```bash
# Ejecutar script de configuración
./scripts/setup-crontab.sh
```

### 6.4 Verificar crontab configurado
```bash
crontab -l
```

Deberías ver:
```
# Monitoreo y autoescalabilidad cada minuto
* * * * * /opt/chat-app/scripts/autoscale.sh --monitor >> /opt/chat-app/logs/autoscale.log 2>&1

# Backup cada 6 horas
0 */6 * * * /opt/chat-app/scripts/backup.sh >> /opt/chat-app/logs/backup.log 2>&1

# Limpieza diaria a las 2 AM
0 2 * * * /opt/chat-app/scripts/cleanup.sh >> /opt/chat-app/logs/cleanup.log 2>&1

# Verificación de salud cada 5 minutos
*/5 * * * * curl -s http://localhost/health > /dev/null 2>&1 || echo 'Health check failed' >> /opt/chat-app/logs/health.log
```

---

## ✅ PASO 7: Verificar Despliegue

### 7.1 Probar acceso a la aplicación
```bash
# Frontend
curl http://localhost

# Backend API
curl http://localhost:3000/api/health

# Nginx
curl http://localhost/health
```

### 7.2 Ver logs de servicios
```bash
# Logs del backend
docker-compose -f docker-compose.prod.yml logs backend

# Logs del frontend
docker-compose -f docker-compose.prod.yml logs frontend

# Logs de Nginx
docker-compose -f docker-compose.prod.yml logs nginx

# Logs en tiempo real
docker-compose -f docker-compose.prod.yml logs -f
```

### 7.3 Verificar estado de autoescalado
```bash
./scripts/autoscale.sh --status
```

Salida esperada:
```
=== Estado del Autoescalado ===
Backends activos: 1
CPU: 25%
Memoria: 45%
Conexiones activas: 0
Última actualización: 2024-01-15 14:30:45
```

---

## 🧪 PASO 8: Pruebas de Autoescalado - Backend

### 8.1 Instalar herramientas de prueba
```bash
# Instalar Apache Bench
sudo apt install -y apache2-utils

# Instalar wrk (herramienta de stress test más potente)
sudo apt install -y build-essential libssl-dev git
git clone https://github.com/wg/wrk.git /tmp/wrk
cd /tmp/wrk
make
sudo cp wrk /usr/local/bin/
cd /opt/chat-app
```

### 8.2 Monitoreo en tiempo real (Terminal 1)
```bash
# Ver estado del autoescalado cada 5 segundos
watch -n 5 'docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}" && echo "---" && ./scripts/autoscale.sh --status'
```

### 8.3 Ver logs de autoescalado (Terminal 2)
```bash
tail -f logs/autoscale.log
```

### 8.4 Ejecutar prueba de carga (Terminal 3)
```bash
# Prueba 1: Carga moderada (30 segundos)
ab -n 1000 -c 50 http://localhost:3000/api/health

# Prueba 2: Carga alta (60 segundos)
wrk -t4 -c100 -d60s http://localhost:3000/api/health

# Prueba 3: Carga muy alta (120 segundos)
wrk -t8 -c200 -d120s http://localhost:3000/api/health
```

### 8.5 Observar resultados
En Terminal 1 deberías ver:
```
Antes de prueba:
chat_backend          Up 5 minutes
Backends activos: 1

Durante prueba (CPU > 80%):
chat_backend          Up 5 minutes
chat_backend_1705334465    Up 1 minute
chat_backend_1705334525    Up 30 seconds
Backends activos: 3

Después de prueba (CPU < 20%):
chat_backend          Up 5 minutes
Backends activos: 1
```

---

## 🌐 PASO 9: Pruebas de Autoescalado - Frontend

### 9.1 Crear script de prueba de conexiones WebSocket
```bash
cat > /tmp/test-websocket.js << 'EOF'
const io = require('socket.io-client');

const NUM_CLIENTS = 50;
const SERVER_URL = 'http://localhost';

console.log(`Conectando ${NUM_CLIENTS} clientes...`);

let connectedCount = 0;

for (let i = 0; i < NUM_CLIENTS; i++) {
  const socket = io(SERVER_URL, {
    reconnection: true,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 5000,
    reconnectionAttempts: 5
  });

  socket.on('connect', () => {
    connectedCount++;
    console.log(`[${new Date().toLocaleTimeString()}] Cliente ${i + 1} conectado. Total: ${connectedCount}`);
    
    // Enviar mensaje cada 5 segundos
    setInterval(() => {
      socket.emit('message', {
        username: `user_${i}`,
        room: 'general',
        text: `Mensaje de prueba ${i} - ${Date.now()}`
      });
    }, 5000);
  });

  socket.on('disconnect', () => {
    console.log(`[${new Date().toLocaleTimeString()}] Cliente ${i + 1} desconectado`);
  });

  socket.on('error', (error) => {
    console.error(`[${new Date().toLocaleTimeString()}] Error en cliente ${i + 1}:`, error);
  });
}

// Mantener el proceso activo
setInterval(() => {
  console.log(`[${new Date().toLocaleTimeString()}] Clientes conectados: ${connectedCount}/${NUM_CLIENTS}`);
}, 10000);
EOF

# Instalar socket.io-client si no está
npm install -g socket.io-client

# Ejecutar prueba
node /tmp/test-websocket.js
```

### 9.2 Alternativa: Usar navegador para pruebas manuales
```bash
# Abrir múltiples pestañas en navegador
# URL: http://<IP_DEL_SERVIDOR>

# En cada pestaña:
# 1. Ingresa un nombre de usuario
# 2. Haz clic en "Conectar"
# 3. Selecciona una sala
# 4. Envía mensajes
```

### 9.3 Monitoreo durante prueba de frontend
```bash
# Terminal 1: Ver backends activos
watch -n 5 'docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}"'

# Terminal 2: Ver logs de autoescalado
tail -f logs/autoscale.log

# Terminal 3: Ver conexiones activas en BD
docker exec chat_db psql -U chatuser -d chatdb -c "SELECT COUNT(*) as conexiones_activas FROM active_connections;"
```

---

## 📊 PASO 10: Análisis de Resultados

### 10.1 Verificar logs de autoescalado
```bash
cat logs/autoscale.log
```

Ejemplo de salida esperada:
```
[2024-01-15 14:30:00] === Monitoreo iniciado ===
[2024-01-15 14:30:05] CPU: 15%, Memoria: 35%, Conexiones: 5
[2024-01-15 14:30:05] Estado: NORMAL - No hay cambios
[2024-01-15 14:35:00] CPU: 82%, Memoria: 88%, Conexiones: 150
[2024-01-15 14:35:00] Estado: ESCALANDO ARRIBA
[2024-01-15 14:35:05] Creando nuevo backend: chat_backend_1705334465
[2024-01-15 14:35:10] Backend creado exitosamente
[2024-01-15 14:35:10] Backends activos: 2
[2024-01-15 14:40:00] CPU: 45%, Memoria: 52%, Conexiones: 150
[2024-01-15 14:40:05] Estado: NORMAL - No hay cambios
[2024-01-15 14:50:00] CPU: 18%, Memoria: 28%, Conexiones: 10
[2024-01-15 14:50:00] Estado: ESCALANDO ABAJO
[2024-01-15 14:50:05] Eliminando backend: chat_backend_1705334465
[2024-01-15 14:50:10] Backend eliminado exitosamente
[2024-01-15 14:50:10] Backends activos: 1
```

### 10.2 Verificar estadísticas de Docker
```bash
# Uso de recursos
docker stats --no-stream

# Historial de contenedores
docker ps -a --filter "name=chat_backend"
```

### 10.3 Verificar base de datos
```bash
# Conexiones activas
docker exec chat_db psql -U chatuser -d chatdb -c "SELECT COUNT(*) FROM active_connections;"

# Mensajes guardados
docker exec chat_db psql -U chatuser -d chatdb -c "SELECT COUNT(*) FROM messages;"

# Usuarios registrados
docker exec chat_db psql -U chatuser -d chatdb -c "SELECT COUNT(*) FROM users;"
```

---

## 🔍 PASO 11: Troubleshooting

### Problema: Los contenedores no inician
```bash
# Ver logs detallados
docker-compose -f docker-compose.prod.yml logs

# Reconstruir sin caché
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml build --no-cache
docker-compose -f docker-compose.prod.yml up -d
```

### Problema: No puedo conectarme a la BD
```bash
# Verificar que la BD está lista
docker-compose -f docker-compose.prod.yml logs db

# Esperar 30 segundos y reintentar
sleep 30
docker-compose -f docker-compose.prod.yml restart backend

# Verificar conexión
docker exec chat_db psql -U chatuser -d chatdb -c "SELECT 1;"
```

### Problema: Crontab no funciona
```bash
# Verificar que los scripts son ejecutables
ls -la scripts/

# Dar permisos si es necesario
chmod +x scripts/*.sh

# Verificar crontab
crontab -l

# Ver logs de cron
grep CRON /var/log/syslog | tail -20

# Ejecutar script manualmente para probar
./scripts/autoscale.sh --monitor
```

### Problema: Falta espacio en disco
```bash
# Ver uso de disco
df -h

# Ejecutar limpieza manual
./scripts/cleanup.sh

# Ver uso de Docker
docker system df

# Limpiar todo (CUIDADO)
docker system prune -a
```

### Problema: Nginx no balancea correctamente
```bash
# Ver configuración de Nginx
docker exec chat_nginx cat /etc/nginx/nginx.conf

# Recargar configuración
docker exec chat_nginx nginx -s reload

# Ver logs de Nginx
docker-compose -f docker-compose.prod.yml logs nginx
```

---

## 📈 PASO 12: Monitoreo Continuo

### 12.1 Crear script de monitoreo personalizado
```bash
cat > /opt/chat-app/scripts/monitor-dashboard.sh << 'EOF'
#!/bin/bash

while true; do
  clear
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║         DASHBOARD DE MONITOREO - Chat en Tiempo Real       ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "📊 ESTADO DE SERVICIOS:"
  docker-compose -f docker-compose.prod.yml ps
  echo ""
  
  echo "🐳 BACKENDS ACTIVOS:"
  docker ps --filter "name=chat_backend" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo ""
  
  echo "💾 USO DE RECURSOS:"
  docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
  echo ""
  
  echo "📈 ESTADO DEL AUTOESCALADO:"
  ./scripts/autoscale.sh --status
  echo ""
  
  echo "🔄 Actualizando en 10 segundos... (Ctrl+C para salir)"
  sleep 10
done
EOF

chmod +x /opt/chat-app/scripts/monitor-dashboard.sh

# Ejecutar
./scripts/monitor-dashboard.sh
```

### 12.2 Ver logs en tiempo real
```bash
# Todos los logs
docker-compose -f docker-compose.prod.yml logs -f

# Solo backend
docker-compose -f docker-compose.prod.yml logs -f backend

# Solo Nginx
docker-compose -f docker-compose.prod.yml logs -f nginx

# Solo autoescalado
tail -f logs/autoscale.log
```

---

## ✨ PASO 13: Optimizaciones Finales

### 13.1 Configurar SSL/TLS (HTTPS)
```bash
# Generar certificados autofirmados (desarrollo)
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem \
  -subj "/C=ES/ST=State/L=City/O=Org/CN=localhost"

# Para producción, usar Let's Encrypt
sudo apt install -y certbot python3-certbot-nginx
sudo certbot certonly --standalone -d tu-dominio.com
```

### 13.2 Configurar backups automáticos
```bash
# Verificar que backups se están creando
ls -la backups/

# Restaurar un backup si es necesario
gunzip backups/chatdb_20240115_143000.sql.gz
docker exec -i chat_db psql -U chatuser -d chatdb < backups/chatdb_20240115_143000.sql
```

### 13.3 Configurar alertas
```bash
# Crear script de alertas
cat > /opt/chat-app/scripts/alert.sh << 'EOF'
#!/bin/bash

# Verificar CPU
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
if (( $(echo "$CPU > 90" | bc -l) )); then
  echo "⚠️ ALERTA: CPU muy alta: ${CPU}%"
fi

# Verificar memoria
MEMORY=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
if (( $(echo "$MEMORY > 90" | bc -l) )); then
  echo "⚠️ ALERTA: Memoria muy alta: ${MEMORY}%"
fi

# Verificar espacio en disco
DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
if [ $DISK -gt 90 ]; then
  echo "⚠️ ALERTA: Disco casi lleno: ${DISK}%"
fi
EOF

chmod +x /opt/chat-app/scripts/alert.sh

# Agregar a crontab
(crontab -l; echo "*/5 * * * * /opt/chat-app/scripts/alert.sh") | crontab -
```

---

## 📋 Checklist Final

- [ ] Ubuntu actualizado
- [ ] Docker instalado y funcionando
- [ ] Docker Compose instalado
- [ ] Proyecto clonado en `/opt/chat-app`
- [ ] Archivo `.env` configurado
- [ ] Imágenes Docker construidas
- [ ] Servicios levantados correctamente
- [ ] Crontab configurado para autoescalado
- [ ] Acceso a frontend en http://localhost
- [ ] Acceso a backend en http://localhost:3000
- [ ] Pruebas de carga ejecutadas
- [ ] Autoescalado funcionando correctamente
- [ ] Logs verificados
- [ ] Backups configurados
- [ ] Monitoreo activo

---

## 🎓 Resumen del Despliegue

```
┌─────────────────────────────────────────────────────────┐
│           ARQUITECTURA FINAL EN PRODUCCIÓN              │
└─────────────────────────────────────────────────────────┘

                    Internet
                       ↓
        ┌──────────────────────────────┐
        │   Nginx (Proxy + LB)         │
        │   Puerto 80/443              │
        └──────────────────────────────┘
                ↓              ↓
    ┌──────────────────┬──────────────────┐
    │                  │                  │
┌─────────────┐   ┌──────────────┐   ┌──────────────┐
│  Frontend   │   │  Backend 1   │   │  Backend N   │
│  (Nginx)    │   │  (Node.js)   │   │  (Dinámico)  │
│ Puerto 3001 │   │ Puerto 3000  │   │ Puerto 300X  │
└─────────────┘   └──────────────┘   └──────────────┘
                        ↓
                ┌──────────────────┐
                │   PostgreSQL     │
                │   (Base de Datos)│
                │   Puerto 5432    │
                └──────────────────┘

Monitoreo: Crontab ejecuta autoscale.sh cada minuto
Escalado: Automático según CPU/Memoria/Conexiones
Backups: Cada 6 horas automáticamente
Logs: Guardados en /opt/chat-app/logs/
```

---

**Versión**: 1.0.0  
**Última actualización**: 2024  
**Ambiente**: Ubuntu Server 20.04+  
**Autor**: René Llanos Machuca & Jhoyce Roxana Pérez Torres
