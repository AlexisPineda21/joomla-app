# Imagen de Joomla construida desde este fork (release 5.4.10 + cambios propios).
#
# Se parte de la imagen oficial para conservar PHP 8.3, Apache, las extensiones
# (mysqli, redis) y su entrypoint, que crea la base de datos e instala Joomla la
# primera vez. Solo se reemplaza el codigo por el del repositorio y se agrega el
# script de arranque.
FROM joomla:5.4.10-php8.3-apache

ARG APP_COMMIT=local

# Codigo del fork en lugar del que trae la imagen
RUN rm -rf /usr/src/joomla && mkdir -p /usr/src/joomla
COPY --chown=www-data:www-data . /usr/src/joomla/

# Scripts de arranque fuera del webroot y .htaccess a partir de htaccess.txt
# (igual que el entrypoint oficial: la imagen de PHP ya desactiva los indices)
RUN set -eux; \
    cd /usr/src/joomla; \
    install -m 0755 docker/start-joomla.sh /usr/local/bin/start-joomla; \
    install -m 0755 docker/apache2-joomla-init /usr/local/bin/apache2-joomla-init; \
    install -m 0644 docker/configure-joomla.php /usr/local/lib/configure-joomla.php; \
    rm -rf docker; \
    sed -E 's/^(Options -Indexes.*)$/#\1/' htaccess.txt > .htaccess; \
    chown www-data:www-data .htaccess; \
    test -f index.php && test -f libraries/src/Version.php && test -f installation/joomla.php

ENV APP_COMMIT=${APP_COMMIT} \
    JOOMLA_DATA_DIR=/mnt/joomla-data

# El ENTRYPOINT oficial (/entrypoint.sh) ejecuta directamente cualquier comando que
# no sea apache2*; start-joomla prepara el sitio y luego arranca Apache.
CMD ["start-joomla"]
