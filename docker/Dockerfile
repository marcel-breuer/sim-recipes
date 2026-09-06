# Server Side Up provides the hardened PHP-FPM + NGINX runtime, Composer,
# PHP CLI, health checks, and Laravel container automations.
FROM serversideup/php:8.4-fpm-nginx

USER root

RUN install-php-extensions gd pdo_pgsql redis

WORKDIR /var/www/html

COPY backend/composer.json backend/composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts

COPY --chown=www-data:www-data backend/ ./

RUN composer dump-autoload \
    --classmap-authoritative \
    --no-dev \
    --no-scripts \
    && mkdir -p storage/framework/cache/data storage/framework/sessions \
        storage/framework/views storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

USER www-data
