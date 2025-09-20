#!/bin/bash

echo "===== MySQL Container Setup Script ====="

# Container name
read -p "Enter MySQL container name: " CONTAINER_NAME

# Root user
read -p "Enter MySQL root username (default: root): " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-root}

# Root password
read -sp "Enter MySQL root password: " MYSQL_PASSWORD
echo ""

# Port
read -p "Enter MySQL port to expose (default: 3306): " MYSQL_PORT
MYSQL_PORT=${MYSQL_PORT:-3306}

# Show existing Docker volumes
echo "Available Docker volumes:"
docker volume ls
read -p "Enter volume name for MySQL data (default: mysql-data): " VOLUME_NAME
VOLUME_NAME=${VOLUME_NAME:-mysql-data}

# Create volume if not exists
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "⚠️ Volume '$VOLUME_NAME' does not exist. Creating..."
  docker volume create "$VOLUME_NAME"
fi

# Show existing Docker networks
echo "Available Docker networks:"
docker network ls
read -p "Enter network name for MySQL (default: bridge): " NETWORK_NAME
NETWORK_NAME=${NETWORK_NAME:-bridge}

# Create network if not exists (ignore if "bridge")
if [ "$NETWORK_NAME" != "bridge" ]; then
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "⚠️ Network '$NETWORK_NAME' does not exist. Creating..."
    docker network create "$NETWORK_NAME"
  fi
fi

# MySQL image
read -p "Enter MySQL image version (default: mysql:8.0): " MYSQL_IMAGE
MYSQL_IMAGE=${MYSQL_IMAGE:-mysql:8.0}

echo "===== Summary ====="
echo "Container Name : $CONTAINER_NAME"
echo "Root User      : $MYSQL_USER"
echo "Port           : $MYSQL_PORT"
echo "Volume         : $VOLUME_NAME"
echo "Network        : $NETWORK_NAME"
echo "Image          : $MYSQL_IMAGE"
echo "==================="

# Remove old container if exists
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  echo "⚠️ Container '$CONTAINER_NAME' already exists. Removing..."
  docker rm -f "$CONTAINER_NAME"
fi

# Run MySQL container
docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK_NAME" \
  -v "$VOLUME_NAME":/var/lib/mysql \
  --restart=always \
  -e MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD" \
  -p "$MYSQL_PORT":3306 \
  "$MYSQL_IMAGE"

echo "✅ MySQL container '$CONTAINER_NAME' started with volume '$VOLUME_NAME' and network '$NETWORK_NAME'."
