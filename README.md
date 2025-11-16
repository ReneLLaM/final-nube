# 💬 Chat en Tiempo Real - Aplicación Contenerizada

Una aplicación moderna de chat en tiempo real desarrollada con **Node.js**, **Socket.io**, **PostgreSQL** y **Docker**. Incluye autoescalabilidad automática mediante scripts de crontab para Linux.

## 📋 Características

- ✅ **Chat en Tiempo Real** - Comunicación instantánea con WebSockets
- ✅ **Múltiples Salas** - Organiza conversaciones por temas
- ✅ **Interfaz Moderna** - Diseño limpio con fondo blanco y colores claros
- ✅ **Autoescalabilidad** - Escalado automático basado en recursos
- ✅ **Persistencia de Datos** - Base de datos PostgreSQL con volúmenes Docker
- ✅ **Proxy Inverso** - Nginx para enrutamiento y balanceo de carga
- ✅ **Monitoreo** - Scripts de monitoreo y backup automáticos
- ✅ **Responsive** - Compatible con dispositivos móviles

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                    Nginx (Proxy)                         │
│              (Puerto 80/443)                             │
└─────────────────────────────────────────────────────────┘
                    ↓              ↓
        ┌───────────────────┬──────────────────┐
        │                   │                  │
    ┌─────────────┐   ┌──────────────┐   ┌──────────────┐
    │  Frontend   │   │   Backend    │   │  PostgreSQL  │
    │  (Nginx)    │   │  (Node.js)   │   │   (BD)       │
    │ Puerto 3001 │   │ Puerto 3000  │   │ Puerto 5432  │
    └─────────────┘   └──────────────┘   └──────────────┘
                           ↓
                    Socket.io (WS)
```

## 📦 Requisitos

- **Docker** 20.10+
- **Docker Compose** 2.0+
- **Linux** (para scripts de crontab)
- **Git** (opcional, para control de versiones)

## 🚀 Instalación Rápida

### 1. Clonar o descargar el proyecto

```bash
cd "chat en tiempo real"
```

### 2. Construir las imágenes Docker

```bash
docker-compose build
```

### 3. Iniciar los servicios

```bash
docker-compose up -d
```

### 4. Verificar que todo está corriendo

```bash
docker-compose ps
```

### 5. Acceder a la aplicación

- **Frontend**: http://localhost (o http://localhost:3001)
- **Backend API**: http://localhost:3000/api/health
- **Nginx**: http://localhost:80

## 🔧 Configuración de Autoescalabilidad

### En Linux (Recomendado)

#### Paso 1: Hacer scripts ejecutables

```bash
chmod +x scripts/*.sh
```

#### Paso 2: Configurar crontab automáticamente

```bash
./scripts/setup-crontab.sh
```

Este script configura automáticamente:
- ✓ Monitoreo cada minuto
- ✓ Backups cada 6 horas
- ✓ Limpieza de logs diariamente
- ✓ Verificación de salud cada 5 minutos
- ✓ Reinicio de servicios semanalmente

#### Paso 3: Verificar crontab

```bash
crontab -l
```

### Configuración Manual de Crontab

Si prefieres configurar manualmente, edita tu crontab:

```bash
crontab -e
```

Y añade estas líneas:

```cron
# Monitoreo y autoescalabilidad cada minuto
* * * * * /ruta/al/proyecto/scripts/autoscale.sh --monitor >> /ruta/al/proyecto/logs/autoscale.log 2>&1

# Backup cada 6 horas
0 */6 * * * /ruta/al/proyecto/scripts/backup.sh >> /ruta/al/proyecto/logs/backup.log 2>&1

# Limpieza diaria a las 2 AM
0 2 * * * /ruta/al/proyecto/scripts/cleanup.sh >> /ruta/al/proyecto/logs/cleanup.log 2>&1

# Verificación de salud cada 5 minutos
*/5 * * * * curl -s http://localhost/health > /dev/null 2>&1 || echo 'Health check failed' >> /ruta/al/proyecto/logs/health.log

# Reinicio semanal (domingo a las 3 AM)
0 3 * * 0 cd /ruta/al/proyecto && docker-compose restart >> /ruta/al/proyecto/logs/restart.log 2>&1
```

## 📊 Monitoreo

### Ver estado actual

```bash
./scripts/autoscale.sh --status
```

### Ver configuración

```bash
./scripts/autoscale.sh --config
```

### Ver logs

```bash
# Logs de autoescalabilidad
tail -f logs/autoscale.log

# Logs de backup
tail -f logs/backup.log

# Logs de limpieza
tail -f logs/cleanup.log

# Logs de salud
tail -f logs/health.log
```

## 🎨 Interfaz de Usuario

La aplicación cuenta con una interfaz moderna y limpia:

- **Fondo Blanco**: Diseño minimalista y profesional
- **Colores Claros**: Paleta de colores suave y agradable
- **Sidebar**: Panel lateral con salas y usuarios conectados
- **Chat Principal**: Área de mensajes con scroll automático
- **Indicador de Escritura**: Muestra cuando otros usuarios están escribiendo
- **Notificaciones**: Alertas en tiempo real de eventos

## 📝 Uso de la Aplicación

1. **Conectarse**: Ingresa tu nombre de usuario y haz clic en "Conectar"
2. **Seleccionar Sala**: Elige una sala de chat del panel lateral
3. **Escribir Mensaje**: Escribe en el campo de entrada y presiona Enter o haz clic en "Enviar"
4. **Ver Usuarios**: Observa quién está conectado en la lista de usuarios
5. **Desconectarse**: Haz clic en "Desconectar" cuando termines

## 🗄️ Base de Datos

### Tablas Principales

- **users**: Usuarios registrados
- **chat_rooms**: Salas de chat disponibles
- **messages**: Historial de mensajes
- **active_connections**: Conexiones activas en tiempo real

### Backups

Los backups se guardan automáticamente en `backups/` con formato:
```
chatdb_YYYYMMDD_HHMMSS.sql.gz
```

### Restaurar Backup

```bash
# Descomprimir
gunzip backups/chatdb_20240101_120000.sql.gz

# Restaurar
docker exec -i chat_db psql -U chatuser -d chatdb < backups/chatdb_20240101_120000.sql
```

## 🔐 Seguridad

- **SSL/TLS**: Nginx está configurado para HTTPS (certificados autofirmados en desarrollo)
- **Rate Limiting**: Protección contra abuso de API
- **CORS**: Configurado para comunicación segura
- **Validación**: Sanitización de entrada en frontend y backend

## 🐛 Troubleshooting

### Los contenedores no inician

```bash
# Ver logs
docker-compose logs -f

# Reconstruir
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### No puedo conectarme a la BD

```bash
# Verificar que la BD está lista
docker-compose logs db

# Esperar 30 segundos y reintentar
sleep 30
docker-compose restart backend
```

### Crontab no funciona

```bash
# Verificar que los scripts son ejecutables
ls -la scripts/

# Dar permisos
chmod +x scripts/*.sh

# Verificar crontab
crontab -l

# Ver logs de cron
grep CRON /var/log/syslog  # Linux
log stream --predicate 'process == "cron"'  # macOS
```

### Falta espacio en disco

```bash
# Ejecutar limpieza manual
./scripts/cleanup.sh

# Ver uso de disco
docker system df

# Limpiar todo
docker system prune -a
```

## 📈 Escalado Manual

### Escalar hacia arriba

```bash
./scripts/autoscale.sh --monitor
```

### Ver réplicas activas

```bash
docker ps --filter "name=chat_backend"
```

### Detener réplica específica

```bash
docker stop chat_backend_<timestamp>
docker rm chat_backend_<timestamp>
```

## 🔄 Actualizar Configuración

### Cambiar umbrales de autoescalabilidad

Edita `config/autoscale.conf`:

```bash
nano config/autoscale.conf
```

### Cambiar variables de entorno

Edita `.env`:

```bash
nano .env
```

Luego reinicia los servicios:

```bash
docker-compose down
docker-compose up -d
```

## 📚 Estructura del Proyecto

```
chat en tiempo real/
├── docker-compose.yml          # Orquestación de servicios
├── init.sql                    # Script de inicialización de BD
├── .env                        # Variables de entorno
├── README.md                   # Este archivo
│
├── backend/
│   ├── Dockerfile             # Imagen del backend
│   ├── package.json           # Dependencias Node.js
│   └── server.js              # Servidor principal
│
├── frontend/
│   ├── Dockerfile             # Imagen del frontend
│   ├── index.html             # Página principal
│   ├── style.css              # Estilos
│   └── script.js              # Lógica del cliente
│
├── nginx/
│   ├── nginx.conf             # Configuración de Nginx
│   └── ssl/                   # Certificados SSL (desarrollo)
│
├── scripts/
│   ├── autoscale.sh           # Autoescalabilidad
│   ├── backup.sh              # Backups de BD
│   ├── cleanup.sh             # Limpieza del sistema
│   └── setup-crontab.sh       # Configuración de crontab
│
├── config/
│   └── autoscale.conf         # Configuración de autoescalabilidad
│
├── logs/                       # Logs de la aplicación
├── backups/                    # Backups de base de datos
└── .gitignore                 # Archivos ignorados por Git
```

## 🤝 Contribuciones

Miembros del Grupo:
- **René Llanos Machuca**
- **Jhoyce Roxana Pérez Torres**

## 📄 Licencia

MIT License - Libre para usar y modificar

## 📞 Soporte

Para reportar problemas o sugerencias:

1. Verifica los logs: `tail -f logs/autoscale.log`
2. Ejecuta diagnóstico: `docker-compose ps`
3. Revisa la sección de Troubleshooting

## 🎯 Próximas Mejoras

- [ ] Autenticación con JWT
- [ ] Encriptación de mensajes
- [ ] Historial de mensajes en frontend
- [ ] Búsqueda de mensajes
- [ ] Reacciones con emojis
- [ ] Compartir archivos
- [ ] Videollamadas
- [ ] Tema oscuro

---

**Última actualización**: 2024
**Versión**: 1.0.0
