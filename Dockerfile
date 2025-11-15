ARG BUILD_DIR=/build
ARG BASE_IMAGE=debian:12-slim

FROM $BASE_IMAGE AS debsuryorg-key

ARG BUILD_DIR
ADD --link https://packages.sury.org/debsuryorg-archive-keyring.deb $BUILD_DIR/debsuryorg-archive-keyring.deb

FROM $BASE_IMAGE

ARG TARGETARCH
ARG TARGETVARIANT
ARG TARGETOS

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

ENV PHP_VERSION=8.3
ENV DEBIAN_FRONTEND=noninteractive

COPY clear-cache /bin/clear-cache

# Use Dockerfile-native mechanisms for PHP repo setup
# Procedure adapted from https://packages.sury.org/php/README.txt
ARG BUILD_DIR
RUN \
  --mount=type=bind,target=$BUILD_DIR,source=$BUILD_DIR,from=debsuryorg-key \
  dpkg -i $BUILD_DIR/debsuryorg-archive-keyring.deb
RUN \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=debian-apt-lists-$TARGETARCH$TARGETVARIANT \
  --mount=type=cache,target=/var/cache/apt/archives,sharing=locked,id=debian-apt-archives-$TARGETARCH$TARGETVARIANT \
<<EOS
set -e
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confnew" --no-install-recommends --no-install-suggests lsb-release ca-certificates
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt-get update
EOS

RUN \
  --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=debian-apt-lists-$TARGETARCH$TARGETVARIANT \
  --mount=type=cache,target=/var/cache/apt/archives,sharing=locked,id=debian-apt-archives-$TARGETARCH$TARGETVARIANT \
<<EOS
set -e
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confnew" --no-install-recommends --no-install-suggests \
  curl \
  git \
  patch \
  openssh-client \
  openssl \
  sudo \
  unzip \
  postgresql-client \
  postgresql-client-common \
  imagemagick \
  poppler-utils \
  apache2 \
  apache2-utils \
  libapache2-mod-php${PHP_VERSION} \
  php${PHP_VERSION} \
  php${PHP_VERSION}-common \
  php${PHP_VERSION}-dev \
  php${PHP_VERSION}-ctype \
  php${PHP_VERSION}-curl \
  php${PHP_VERSION}-fileinfo \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-iconv \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-pgsql \
  php${PHP_VERSION}-phar \
  php${PHP_VERSION}-pdo \
  php${PHP_VERSION}-simplexml \
  php${PHP_VERSION}-tokenizer \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-zip \
  php${PHP_VERSION}-memcached \
  libmemcached-tools \
  php${PHP_VERSION}-intl \
  php${PHP_VERSION}-apcu \
  gh
EOS

# renovate: datasource=github-tags depName=mikefarah/yq
ARG YQ_VERSION=v4.48.2
ADD --chmod=555 https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${TARGETOS}_${TARGETARCH} /usr/local/bin/yq

ENV PHP_INI_DIR=/etc/php/$PHP_VERSION
ENV DGI_PHP_INI=/etc/php/dgi/99-config.ini

# Use the DGI_PHP_INI variable directly for copying config
COPY --link dgi_99-config.ini ${DGI_PHP_INI}
RUN ln -s ${DGI_PHP_INI} ${PHP_INI_DIR}/apache2/conf.d/99-config.ini \
  && ln -s ${DGI_PHP_INI} ${PHP_INI_DIR}/cli/conf.d/99-config.ini
# Back out to the original WORKDIR.
WORKDIR /

# setup apache2
COPY --link rootfs/etc/apache2/conf-available/logging.conf /etc/apache2/conf-available/logging.conf

RUN <<EOS
set -e
a2enconf logging.conf
chown -R www-data /var/log/apache2
EOS

# disable and enable sites
RUN a2dissite default-ssl.conf \
  && a2dissite 000-default.conf

COPY --link rootfs/etc/apache2/sites-available/25-80-dgi.conf /etc/apache2/sites-available/
RUN a2ensite 25-80-dgi.conf

COPY --link rootfs/etc/ImageMagick-6/policy.xml /etc/ImageMagick-6/policy.xml

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

# Migration sillyness
COPY <<EOCONF /etc/security/limits.d/migration.conf
* soft nofile -1
* hard nofile -1
EOCONF

USER root

WORKDIR ${DRUPAL_ROOT}

CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
