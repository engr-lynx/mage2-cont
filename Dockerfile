FROM public.ecr.aws/z0z6r0u2/magento2-php-apache:latest

# Copy Magento2 project and install dependencies
ARG MP_USERNAME
ARG MP_PASSWORD
COPY ./ ./
RUN MAGENTO_AUTH_FILE=${COMPOSER_HOME}/auth.json \
  && cp ./auth.json.sample ${MAGENTO_AUTH_FILE} \
  && sed -i "s/<public-key>/${MP_USERNAME}/" ${MAGENTO_AUTH_FILE} \
  && sed -i "s/<private-key>/${MP_PASSWORD}/" ${MAGENTO_AUTH_FILE} \
  && RETRIES=3; SLEEP=3; i=0; \
  while [ ${i} -lt ${RETRIES} ]; do \
    composer update; \
    RES=$?; \
    if [ ${RES} -eq 0 ]; then \
      break; \
    fi; \
    i=$((i+1)); \
    sleep ${SLEEP}; \
  done && return ${RES}

# Install Magento2
ARG BASE_URL
ARG ADMIN_URL_PATH
ARG ADMIN_FIRSTNAME
ARG ADMIN_LASTNAME
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
    --admin-firstname="${ADMIN_FIRSTNAME}" \
    --admin-lastname="${ADMIN_LASTNAME}" \
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
