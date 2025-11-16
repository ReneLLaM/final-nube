#!/bin/bash

# Script para esperar a que PostgreSQL esté listo

set -e

host="$1"
port="$2"
shift 2
cmd="$@"

echo "Esperando a que PostgreSQL esté disponible en $host:$port..."

until nc -z "$host" "$port"; do
  >&2 echo "PostgreSQL no está disponible aún - esperando..."
  sleep 1
done

>&2 echo "PostgreSQL está disponible - iniciando aplicación"
exec $cmd
