# 🚀 Autoescalado Explicado - Chat en Tiempo Real

## ¿Qué es el Autoescalado?

El autoescalado es un mecanismo que **aumenta o disminuye automáticamente** el número de instancias del backend según la carga del sistema. Cuando hay muchos usuarios conectados, se crean más contenedores. Cuando la carga baja, se eliminan los innecesarios.

## 🏗️ Arquitectura del Autoescalado

```
┌─────────────────────────────────────────────────────────┐
│                   Nginx (Balanceador)                    │
│              Distribuye tráfico entre backends           │
└─────────────────────────────────────────────────────────┘
                    ↓              ↓              ↓
        ┌───────────────────┬──────────────────┬──────────────┐
        │                   │                  │              │
    ┌─────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │  Backend 1  │   │  Backend 2   │   │  Backend 3   │   │  Backend N   │
    │ (Puerto 3000)   │ (Puerto 3001)   │ (Puerto 3002)   │ (Puerto 300X)   │
    └─────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
                           ↓              ↓              ↓
                    ┌─────────────────────────────────────┐
                    │      PostgreSQL (Base de Datos)     │
                    │         (Compartida)                │
                    └─────────────────────────────────────┘
```

## 📊 Métricas Monitoreadas

El script `autoscale.sh` monitorea continuamente:

### 1. **CPU**
- Umbral mínimo: 20%
- Umbral máximo: 80%
- Si CPU > 80% → Crear nueva instancia
- Si CPU < 20% → Eliminar instancia

### 2. **Memoria**
- Umbral mínimo: 30%
- Umbral máximo: 85%
- Si Memoria > 85% → Crear nueva instancia
- Si Memoria < 30% → Eliminar instancia

### 3. **Conexiones Activas**
- Se consulta la tabla `active_connections` en PostgreSQL
- Si conexiones > 100 → Crear nueva instancia
- Si conexiones < 20 → Eliminar instancia

## 🔄 Flujo de Autoescalado

### Paso 1: Monitoreo (Cada minuto)
```bash
# El crontab ejecuta cada minuto:
* * * * * /ruta/al/proyecto/scripts/autoscale.sh --monitor
```

### Paso 2: Recolección de Métricas
```bash
# El script obtiene:
- CPU actual del sistema
- Memoria disponible
- Número de conexiones activas
- Número de backends corriendo
```

### Paso 3: Evaluación de Decisión
```
¿CPU > 80% O Memoria > 85% O Conexiones > 100?
    ↓ SÍ
    Crear nueva instancia backend
    
¿CPU < 20% Y Memoria < 30% Y Conexiones < 20?
    ↓ SÍ
    Eliminar una instancia backend
    
¿Dentro de rangos normales?
    ↓ SÍ
    No hacer nada
```

### Paso 4: Ejecución
Si se decide crear una instancia:
```bash
docker run -d \
  --name chat_backend_$(date +%s) \
  --network chat_network \
  -e DB_HOST=db \
  -e DB_PORT=5432 \
  -e DB_USER=chatuser \
  -e DB_PASSWORD=chatpass123 \
  -e DB_NAME=chatdb \
  -p <PUERTO_DINAMICO>:3000 \
  chat_backend_image
```

Si se decide eliminar una instancia:
```bash
docker stop chat_backend_<timestamp>
docker rm chat_backend_<timestamp>
```

## 🔧 Configuración en Ubuntu Server

### 1. Preparar el Servidor
```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Instalar Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Agregar usuario actual al grupo docker
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Clonar el Proyecto
```bash
cd /opt
sudo git clone <tu-repositorio> chat-app
cd chat-app
sudo chown -R $USER:$USER .
```

### 3. Hacer Scripts Ejecutables
```bash
chmod +x scripts/*.sh
```

### 4. Configurar Crontab
```bash
# Editar crontab
crontab -e

# Agregar estas líneas:
# Monitoreo cada minuto
* * * * * /opt/chat-app/scripts/autoscale.sh --monitor >> /opt/chat-app/logs/autoscale.log 2>&1

# Backup cada 6 horas
0 */6 * * * /opt/chat-app/scripts/backup.sh >> /opt/chat-app/logs/backup.log 2>&1

# Limpieza diaria a las 2 AM
0 2 * * * /opt/chat-app/scripts/cleanup.sh >> /opt/chat-app/logs/cleanup.log 2>&1

# Verificación de salud cada 5 minutos
*/5 * * * * curl -s http://localhost/health > /dev/null 2>&1 || echo 'Health check failed' >> /opt/chat-app/logs/health.log
```

### 5. Iniciar la Aplicación
```bash
docker-compose up -d
```

## 📈 Ejemplo de Escalado en Acción

### Escenario: Aumento de Usuarios

**Minuto 0**: Sistema en reposo
```
Backends activos: 1
CPU: 15%
Memoria: 25%
Conexiones: 5
```

**Minuto 5**: Llegan 50 usuarios
```
Backends activos: 1
CPU: 78%
Memoria: 82%
Conexiones: 50
→ Decisión: CPU > 80% Y Memoria > 85%
→ Acción: Crear Backend 2
```

**Minuto 6**: Sistema balanceado
```
Backends activos: 2
CPU: 45% (distribuido)
Memoria: 50% (distribuido)
Conexiones: 50 (25 por backend)
→ Decisión: Dentro de rangos normales
→ Acción: Ninguna
```

**Minuto 10**: Llegan 100 usuarios más
```
Backends activos: 2
CPU: 82%
Memoria: 88%
Conexiones: 150
→ Decisión: CPU > 80% Y Conexiones > 100
→ Acción: Crear Backend 3
```

**Minuto 20**: Usuarios se desconectan
```
Backends activos: 3
CPU: 18%
Memoria: 28%
Conexiones: 15
→ Decisión: CPU < 20% Y Memoria < 30% Y Conexiones < 20
→ Acción: Eliminar Backend 3
```

## 🔍 Monitoreo y Logs

### Ver Estado Actual
```bash
./scripts/autoscale.sh --status
```

Salida esperada:
```
=== Estado del Autoescalado ===
Backends activos: 2
CPU: 45%
Memoria: 52%
Conexiones activas: 78
Última actualización: 2024-01-15 14:30:45
```

### Ver Logs en Tiempo Real
```bash
# Logs de autoescalado
tail -f logs/autoscale.log

# Logs de Docker
docker-compose logs -f backend

# Logs de Nginx (balanceador)
docker-compose logs -f nginx
```

### Logs Típicos
```
[2024-01-15 14:30:00] Monitoreo iniciado
[2024-01-15 14:30:05] CPU: 45%, Memoria: 52%, Conexiones: 78
[2024-01-15 14:30:05] Estado: NORMAL
[2024-01-15 14:31:00] CPU: 82%, Memoria: 88%, Conexiones: 150
[2024-01-15 14:31:00] Estado: ESCALANDO ARRIBA
[2024-01-15 14:31:05] Creando nuevo backend: chat_backend_1705334465
[2024-01-15 14:31:10] Backend creado exitosamente
[2024-01-15 14:31:10] Backends activos: 3
```

## ⚙️ Configuración Personalizada

### Editar Umbrales
Archivo: `config/autoscale.conf`

```bash
# Umbrales de CPU (%)
CPU_MIN=20
CPU_MAX=80

# Umbrales de Memoria (%)
MEMORY_MIN=30
MEMORY_MAX=85

# Umbrales de Conexiones
CONNECTIONS_MIN=20
CONNECTIONS_MAX=100

# Máximo de backends permitidos
MAX_BACKENDS=10

# Mínimo de backends siempre activos
MIN_BACKENDS=1
```

### Cambiar Intervalo de Monitoreo
En crontab:
```bash
# Cada minuto (actual)
* * * * * /opt/chat-app/scripts/autoscale.sh --monitor

# Cada 30 segundos (más frecuente)
* * * * * /opt/chat-app/scripts/autoscale.sh --monitor
* * * * * sleep 30 && /opt/chat-app/scripts/autoscale.sh --monitor

# Cada 5 minutos (menos frecuente)
*/5 * * * * /opt/chat-app/scripts/autoscale.sh --monitor
```

## 🛡️ Consideraciones de Seguridad

### 1. **Límites de Recursos**
```yaml
# En docker-compose.yml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### 2. **Reintentos en Caso de Fallo**
```bash
# El script verifica que el backend esté listo
docker exec chat_backend_<id> curl -s http://localhost:3000/health
```

### 3. **Prevención de Cascadas**
- Espera 30 segundos antes de eliminar un backend
- Máximo 1 cambio por minuto
- Mantiene mínimo 1 backend siempre activo

## 📋 Checklist de Implementación en Ubuntu

- [ ] Docker instalado y funcionando
- [ ] Docker Compose instalado
- [ ] Proyecto clonado en `/opt/chat-app`
- [ ] Scripts con permisos ejecutables (`chmod +x scripts/*.sh`)
- [ ] Archivo `.env` configurado
- [ ] Crontab configurado (`crontab -e`)
- [ ] Contenedores iniciados (`docker-compose up -d`)
- [ ] Logs verificados (`tail -f logs/autoscale.log`)
- [ ] Health check funcionando (`curl http://localhost/health`)

## 🚨 Troubleshooting

### El autoescalado no funciona
```bash
# Verificar que crontab está activo
crontab -l

# Ver logs de cron
grep CRON /var/log/syslog | tail -20

# Ejecutar script manualmente
./scripts/autoscale.sh --monitor

# Ver logs
tail -f logs/autoscale.log
```

### Backends no se crean
```bash
# Verificar que la imagen existe
docker images | grep chat_backend

# Verificar red Docker
docker network ls

# Ver logs de Docker
docker-compose logs backend
```

### Memoria no se libera
```bash
# Limpiar contenedores detenidos
docker container prune -f

# Limpiar volúmenes no usados
docker volume prune -f

# Ejecutar limpieza manual
./scripts/cleanup.sh
```

---

**Versión**: 1.0.0  
**Última actualización**: 2024  
**Ambiente**: Ubuntu Server 20.04+
