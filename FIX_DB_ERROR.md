# 🔧 Solución: Error en chat_db - Restarting

## Problema
El contenedor `chat_db` está en estado `Restarting` y no inicia correctamente.

## Causas Comunes
1. Volumen `db_data` corrupto o con datos previos
2. Permisos incorrectos en el volumen
3. Puerto 5432 ya está en uso
4. Falta de espacio en disco

---

## ✅ Solución Paso a Paso

### Paso 1: Detener todos los servicios
```bash
cd /opt/final-nube
docker-compose -f docker-compose.prod.yml down
```

### Paso 2: Eliminar el volumen de BD (CUIDADO: Borra datos)
```bash
# Ver volúmenes
docker volume ls | grep chat

# Eliminar volumen específico
docker volume rm final-nube_db_data

# O eliminar todos los volúmenes del proyecto
docker-compose -f docker-compose.prod.yml down -v
```

### Paso 3: Limpiar contenedores e imágenes (opcional)
```bash
# Eliminar contenedores detenidos
docker container prune -f

# Eliminar imágenes no usadas
docker image prune -f
```

### Paso 4: Reconstruir imágenes sin caché
```bash
docker-compose -f docker-compose.prod.yml build --no-cache
```

### Paso 5: Levantar servicios nuevamente
```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Paso 6: Esperar a que PostgreSQL esté listo
```bash
# Esperar 30 segundos
sleep 30

# Ver logs de la BD
docker-compose -f docker-compose.prod.yml logs db
```

Deberías ver:
```
db_1  | LOG:  database system is ready to accept connections
```

### Paso 7: Verificar estado
```bash
docker-compose -f docker-compose.prod.yml ps
```

Salida esperada:
```
NAME            IMAGE                  COMMAND                  SERVICE    STATUS
chat_db         postgres:15-alpine     "docker-entrypoint.s…"   db         Up 20s
chat_backend    chat-backend:latest    "docker-entrypoint.s…"   backend    Up 15s
chat_frontend   chat-frontend:latest   "/docker-entrypoint.…"   frontend   Up 10s
chat_nginx      nginx:alpine           "nginx -g daemon off…"   nginx      Up 5s
```

---

## 🔍 Si Sigue Sin Funcionar

### Opción 1: Ver logs detallados
```bash
docker-compose -f docker-compose.prod.yml logs -f db
```

### Opción 2: Verificar puerto 5432
```bash
# Ver si algo está usando el puerto
sudo lsof -i :5432

# Si está en uso, matar el proceso
sudo kill -9 <PID>
```

### Opción 3: Verificar espacio en disco
```bash
# Ver uso de disco
df -h

# Si está lleno, limpiar
docker system prune -a
```

### Opción 4: Reconstruir todo desde cero
```bash
# Parar todo
docker-compose -f docker-compose.prod.yml down -v

# Limpiar todo
docker system prune -a --volumes

# Reconstruir
docker-compose -f docker-compose.prod.yml build --no-cache

# Levantar
docker-compose -f docker-compose.prod.yml up -d

# Esperar
sleep 30

# Verificar
docker-compose -f docker-compose.prod.yml ps
```

---

## 📋 Checklist de Verificación

- [ ] Todos los contenedores en estado `Up`
- [ ] `chat_db` no está en `Restarting`
- [ ] `chat_backend` está `Up`
- [ ] `chat_frontend` está `Up`
- [ ] `chat_nginx` está `Up`
- [ ] Puedo acceder a http://localhost
- [ ] Puedo acceder a http://localhost:3000/api/health

---

## 🚀 Comandos Rápidos

```bash
# Limpiar y reiniciar (opción nuclear)
docker-compose -f docker-compose.prod.yml down -v && \
docker-compose -f docker-compose.prod.yml build --no-cache && \
docker-compose -f docker-compose.prod.yml up -d && \
sleep 30 && \
docker-compose -f docker-compose.prod.yml ps
```

---

Si el problema persiste, comparte el output de:
```bash
docker-compose -f docker-compose.prod.yml logs db
```
