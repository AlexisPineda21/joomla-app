#!/bin/bash
# ---------------------------------------------------------------------------
# Arranque del contenedor de Joomla (ECS Fargate y Docker Compose local).
#
# El codigo vive en la imagen (/usr/src/joomla) y se copia en cada arranque al
# webroot local del contenedor (/var/www/html). En el almacenamiento persistente
# (EFS en AWS, un volumen en local) solo quedan configuration.php y images/, que
# se enlazan al webroot. Asi, cada imagen nueva publica su codigo sin tocar los
# datos del sitio, y dos versiones pueden correr a la vez durante un despliegue.
#
#   Primer arranque (no hay configuration.php en el volumen):
#     1. El entrypoint oficial crea la base de datos e instala Joomla con JOOMLA_*.
#     2. Se configura Valkey (cache en DB 0, sesiones en DB 1).
#     3. configuration.php e images/ se mueven al volumen persistente.
#   Arranques siguientes:
#     copia el codigo, quita installation/, enlaza los datos y sincroniza la
#     configuracion con las variables de entorno.
# ---------------------------------------------------------------------------
set -euo pipefail

WEBROOT=/var/www/html
SOURCE=/usr/src/joomla
DATA="${JOOMLA_DATA_DIR:-/mnt/joomla-data}"
CONFIG="$DATA/configuration.php"
LOCK="$DATA/.install-lock"
CONFIGURE=/usr/local/lib/configure-joomla.php

log() { echo "[start-joomla] $*"; }

copy_code() {
  log "Copiando el codigo de la imagen (commit ${APP_COMMIT:-desconocido}) al webroot"
  find "$WEBROOT" -mindepth 1 -delete
  tar -C "$SOURCE" -cf - . | tar -C "$WEBROOT" -xf -
}

link_data() {
  rm -rf "$WEBROOT/images" "$WEBROOT/configuration.php"
  ln -s "$DATA/images" "$WEBROOT/images"
  ln -s "$CONFIG" "$WEBROOT/configuration.php"
  chown -R -h www-data:www-data "$WEBROOT"
}

first_install() {
  copy_code
  # El entrypoint oficial solo inicializa Joomla con comandos que empiezan por "apache2".
  # apache2-joomla-init no hace nada: permite instalar sin arrancar Apache todavia.
  /entrypoint.sh apache2-joomla-init
  php "$CONFIGURE" "$WEBROOT/configuration.php"

  log "Moviendo configuration.php e images/ al almacenamiento persistente"
  if [ ! -d "$DATA/images" ]; then
    cp -a "$WEBROOT/images" "$DATA/images.tmp"
    mv "$DATA/images.tmp" "$DATA/images"
  fi
  cp "$WEBROOT/configuration.php" "$CONFIG.tmp"
  chown www-data:www-data "$CONFIG.tmp"
  chmod 0444 "$CONFIG.tmp"
  mv -f "$CONFIG.tmp" "$CONFIG"
  chown -R www-data:www-data "$DATA/images"
}

# Espera a que otra tarea termine la instalacion. Si el candado tiene mas de
# 20 minutos se considera abandonado (la tarea que instalaba murio).
wait_for_installer() {
  local waited=0
  while [ ! -s "$CONFIG" ]; do
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +20 2>/dev/null)" ]; then
      log "El candado de instalacion esta abandonado; se retira"
      rmdir "$LOCK" 2>/dev/null || true
      return 1
    fi
    if [ "$waited" -ge 1200 ]; then
      log "La instalacion de otra tarea no termino en 20 minutos" >&2
      exit 1
    fi
    log "Otra tarea esta instalando Joomla; esperando..."
    sleep 10
    waited=$((waited + 10))
  done
}

# El entrypoint oficial toma como webroot el directorio actual
cd "$WEBROOT"
mkdir -p "$DATA"
installed_here=false

until [ -s "$CONFIG" ]; do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
    log "Primer arranque: instalando Joomla"
    first_install
    rmdir "$LOCK"
    trap - EXIT
    installed_here=true
  else
    wait_for_installer || true
  fi
done

if [ "$installed_here" = false ]; then
  copy_code
  rm -rf "$WEBROOT/installation"
fi
link_data
php "$CONFIGURE" "$CONFIG"

log "Iniciando Apache"
exec /entrypoint.sh apache2-foreground
