FROM debian:12-slim

ARG TARGETARCH
ARG TARGETVARIANT

EXPOSE 80

ENV DRUPAL_ROOT=/opt/www/drupal
ENV DRUPAL_WEB_ROOT=${DRUPAL_ROOT}/web
ENV DRUPAL_PRIVATE_FILESYSTEM=/opt/drupal_private_filesystems/d8/default
ENV DRUPAL_PUBLIC_FILESYSTEM=${DRUPAL_WEB_ROOT}/sites/default/files
ENV DRUPAL_ISLANDORA_DATA=/opt/islandora_data

ENV DRUPAL_DB_NAME=drupal
ENV DRUPAL_DB_USER=drupal
ENV DRUPAL_DB_PASSWORD=drupal
ENV DRUPAL_TRUSTED_HOSTS='["drupal","localhost"]'
ENV POSTGRES_HOST=db
ENV MEMCACHED_HOST=memcached
ENV MEMCACHED_PORT=11211
ENV SOLR_HOST=solr
ENV SOLR_USERNAME=drupal
ENV SOLR_PASSWORD=drupal
ENV JWT_KEY_TYPE=RS256
ENV JWT_KEY_FILE="/var/run/secrets/crayfish.key"
ENV IIIF_URL=http://cantaloupe/iiif/2
ENV IIIF_INGRESS_URL=http://drupal/iiif/2
ENV ACTIVEMQ_HOST=activemq
ENV ACTIVEMQ_STOMP_PORT=61613
ENV CONFIG_SPLITS='{\
  "prod": true,\
  "dev": false,\
}'
# File location may differ if using file based secrets.
ENV FLYSYSTEM_CONFIG_FILE=${DRUPAL_WEB_ROOT}/sites/default/flysystem_config.json
ENV CLAMAV_HOST=clamav
ENV CLAMAV_PORT=3310

# For configuration of islandora_hocr/the Solr Highlighting Plugin.
ENV SOLR_HOME=/var/solr/data
ENV SOLR_HOCR_PLUGIN_PATH=${SOLR_HOME}/contrib/ocrhighlighting/lib

RUN \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=debian-apt-lists-$TARGETARCH$TARGETVARIANT \
  --mount=type=cache,target=/var/cache/apt/archives,sharing=locked,id=debian-apt-archives-$TARGETARCH$TARGETVARIANT \
  apt-get -qqy update && apt-get -qqy --no-install-recommends install \
     ca-certificates curl git patch openssh-client openssl sudo unzip wget \
     postgresql-client postgresql-client-common \
     imagemagick poppler-utils \
     apache2 apache2-utils php php-common php-dev libapache2-mod-php \
     php-ctype php-curl php-fileinfo php-gd php-iconv php-json \
     php-mbstring php-pgsql php-phar php-pdo \
     php-simplexml php-tokenizer php-xml php-zip \
     php-memcached libmemcached-tools \
     php-intl php-apcu

#--------------------------------------------------------------
# setup PHP
ENV PHP_INI_DIR=/etc/php/8.2
WORKDIR $PHP_INI_DIR
COPY --link dgi_99-config.ini dgi/conf.d/99-config.ini
RUN ln -s $PHP_INI_DIR/dgi/conf.d/99-config.ini apache2/conf.d/99-config.ini \
  && ln -s $PHP_INI_DIR/dgi/conf.d/99-config.ini cli/conf.d/99-config.ini
# Back out to the original WORKDIR.
WORKDIR /

# setup apache2
#RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf \
RUN echo 'ErrorLog /dev/stderr' >> /etc/apache2/apache2.conf \
  && echo 'TransferLog /dev/stdout' >> /etc/apache2/apache2.conf \
  && echo 'CustomLog /dev/stdout combined' >> /etc/apache2/apache2.conf \
  && chown -R www-data /var/log/apache2

# disable and enable sites
RUN a2dissite default-ssl.conf \
  && a2dissite 000-default.conf

COPY --link 25-80-dgi.conf /etc/apache2/sites-available/
RUN a2ensite 25-80-dgi.conf

# enable apache2 modules and sites
RUN a2enmod rewrite \
  && a2enmod ssl \
  && a2enmod proxy_http \
  && a2enmod headers

# setup volumes
RUN mkdir -p ${DRUPAL_ISLANDORA_DATA}/repo-meta \
  && chown -R www-data:www-data ${DRUPAL_ISLANDORA_DATA} \
  && mkdir -p ${DRUPAL_PRIVATE_FILESYSTEM} \
  && chown -R www-data:www-data ${DRUPAL_PRIVATE_FILESYSTEM} \
  && chmod -R 770 ${DRUPAL_PRIVATE_FILESYSTEM} \
  && mkdir -p ${DRUPAL_PUBLIC_FILESYSTEM} \
  && chown www-data:www-data ${DRUPAL_PUBLIC_FILESYSTEM}

VOLUME ["${DRUPAL_ISLANDORA_DATA}", "${DRUPAL_PRIVATE_FILESYSTEM}", "${DRUPAL_PUBLIC_FILESYSTEM}"]
#--------------------------------------------------------------

USER root

WORKDIR ${DRUPAL_ROOT}

CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
