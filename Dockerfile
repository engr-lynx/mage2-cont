# using public.ecr.aws/z0z6r0u2/php7.4-apache:latest instead of php:7.4-apache because Docker Hub sometimes throttles requests
FROM public.ecr.aws/z0z6r0u2/php7.4-apache:latest
# FROM php:7.4-apache

# Install Linux library dependencies
RUN apt-get update \
  && apt-get install -y \
    zip \
    unzip \
    libjpeg-dev \
    libfreetype6-dev \
    zlib1g-dev \
    libpng-dev \
    libicu-dev \
    libxml2-dev \
    libxslt-dev \
    libzip-dev

# Install PHP module dependencies
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install \
    gd \
    intl \
    pdo_mysql \
    soap \
    xsl \
    zip \
    sockets \
    bcmath

# Install Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
  && php -r "if (hash_file('sha384', 'composer-setup.php') === '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
  && php composer-setup.php \
  && php -r "unlink('composer-setup.php');" \
  && mv composer.phar /usr/local/bin/composer

# Configure Apache
RUN a2enmod rewrite
COPY ./apache.conf.sample ${APACHE_CONFDIR}/sites-available/000-default.conf

# Configure PHP
RUN mv "${PHP_INI_DIR}/php.ini-production" "${PHP_INI_DIR}/php.ini" \
  && sed -i "s/memory_limit = /memory_limit = -1 ;/" "${PHP_INI_DIR}/php.ini"

# Magento2 environment
ARG MAGENTO2_HOME="/var/www/magento2"
ARG COMPOSER_ROOT_HOME="/root/.composer"
ARG COMPOSER_PROJ_HOME="${MAGENTO2_HOME}/var/composer_home"
WORKDIR ${MAGENTO2_HOME}
RUN mkdir -p ${COMPOSER_ROOT_HOME} \
  && mkdir -p ${COMPOSER_PROJ_HOME}

# Copy Magento2 project and install dependencies
ARG MP_USERNAME
ARG MP_PASSWORD
COPY ./ ./
RUN MAGENTO_ROOT_AUTH_FILE="${COMPOSER_ROOT_HOME}/auth.json" \
  && cp ./auth.json.sample ${MAGENTO_ROOT_AUTH_FILE} \
  && sed -i "s/<public-key>/${MP_USERNAME}/" ${MAGENTO_ROOT_AUTH_FILE} \
  && sed -i "s/<private-key>/${MP_PASSWORD}/" ${MAGENTO_ROOT_AUTH_FILE} \
  && cp ${MAGENTO_ROOT_AUTH_FILE} ${COMPOSER_PROJ_HOME} \
  && RETRIES=3; SLEEP=3; i=0; \
  while [ ${i} -lt ${RETRIES} ]; do \
    composer install; \
    RES=$?; \
    if [ ${RES} -eq 0 ]; then \
      break; \
    fi; \
    i=$((i+1)); \
    sleep ${SLEEP}; \
  done && return ${RES}

# Deploy Magento2 sample data
ARG DEPLOY_SAMPLE
RUN RES=0; \
  if [ "${DEPLOY_SAMPLE}" = "true" ]; then \
    RETRIES=3; SLEEP=3; i=0; \
    while [ ${i} -lt ${RETRIES} ]; do \
      bin/magento sampledata:deploy; \
      RES=$?; \
      if [ ${RES} -eq 0 ]; then \
        break; \
      fi; \
      i=$((i+1)); \
      sleep ${SLEEP}; \
    done; \
  fi && return ${RES}

# Install Magento2
ARG BASE_URL
ARG ADMIN_URL_PATH
ARG ADMIN_FIRST_NAME
ARG ADMIN_LAST_NAME
ARG ADMIN_EMAIL
ARG ADMIN_USERNAME
ARG ADMIN_PASSWORD
ARG DB_HOST
ARG DB_NAME
ARG DB_USERNAME
ARG DB_PASSWORD
ARG ES_HOST
ARG ES_USERNAME
ARG ES_PASSWORD
RUN bin/magento setup:install \
    --base-url="${BASE_URL}" \
    --use-secure=0 \
    --use-secure-admin=0 \
    --session-save=db \
    --db-host="${DB_HOST}" \
    --db-name="${DB_NAME}" \
    --db-user="${DB_USERNAME}" \
    --db-password="${DB_PASSWORD}" \
    --search-engine=elasticsearch7 \
    --elasticsearch-host="${ES_HOST}" \
    --elasticsearch-port=443 \
    --elasticsearch-enable-auth=1 \
    --elasticsearch-username="${ES_USERNAME}" \
    --elasticsearch-password="${ES_PASSWORD}" \
    --backend-frontname="${ADMIN_URL_PATH}" \
    --admin-firstname="${ADMIN_FIRST_NAME}" \
    --admin-lastname="${ADMIN_LAST_NAME}" \
    --admin-email="${ADMIN_EMAIL}" \
    --admin-user="${ADMIN_USERNAME}" \
    --admin-password="${ADMIN_PASSWORD}" \
    --language=en_US \
    --currency=USD \
    --timezone=America/Chicago \
    --use-rewrites=1

# ToDo: Fix images not showing up: https://magento.stackexchange.com/questions/255890/images-are-not-displaying-after-installation-of-sample-data-in-magento-2-3
# Set Magento2 for production mode w/ disabled 2FA
RUN bin/magento module:disable Magento_TwoFactorAuth \
  && bin/magento deploy:mode:set production \
  && bin/magento cache:flush \
  && chmod -R 777 var
