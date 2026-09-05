FROM php:8.4-cli

RUN apt-get update \
    && apt-get install --no-install-recommends --yes libpq-dev unzip \
    && docker-php-ext-install pdo_pgsql \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-progress \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts

COPY . .
RUN composer dump-autoload --classmap-authoritative --no-dev --no-scripts

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php artisan about --only=environment >/dev/null || exit 1

CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]
