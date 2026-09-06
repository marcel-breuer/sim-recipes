# Deployment support

Deployment-specific assets and documentation belong in this directory.

The canonical deployment file is `docker/docker-compose.yml`. It builds the API
from `docker/Dockerfile`, which extends Server Side Up's `serversideup/php`
8.4 FPM/NGINX image. Do not expose PostgreSQL or Redis publicly.

## Local stack

Create a local environment file from the committed example and replace the
placeholder secrets:

    cp docker/.env.example docker/.env
    # Use FILESYSTEM_DISK=local for a disposable local stack.
    docker compose --env-file docker/.env -f docker/docker-compose.yml up -d --build

The API is available on the port configured by `API_PORT`, defaulting to 8000.
The API container runs Laravel migrations through Server Side Up's autorun
configuration before it becomes healthy. The queue and scheduler wait for that
healthy API container and use the same application image.

Seed the X-S20 camera catalog explicitly on a new database:

    docker compose --env-file docker/.env -f docker/docker-compose.yml \
        exec api php artisan db:seed --force

Use `docker compose ps` and `docker compose logs` to inspect the stack. Stop it
with `docker compose down`; named PostgreSQL and Redis volumes are retained.

## Coolify deployment

Configure the repository as a Docker Compose application in Coolify and select
`docker/docker-compose.yml`. Import the variable names from
`docker/.env.example` and provide production values as Coolify runtime
environment variables, including `APP_KEY`, database/Redis passwords, and
S3-compatible storage credentials. Set `AUTORUN_LARAVEL_MIGRATION_SEED=true`
for the first deployment only, then set it back to `false`. Do not commit the
resulting `.env` file.

Route only the `api` service to the public domain on container port 8080.
The queue and scheduler are worker services, while PostgreSQL and Redis have no
published ports and must remain private to the Compose network. Attach
persistent volumes to postgres_data and redis_data.

The API image uses Server Side Up's unprivileged `www-data` runtime, PHP 8.4,
NGINX, PHP-FPM, Composer, PostgreSQL, GD, and Redis extensions. The queue and
scheduler use the same application image with dedicated Artisan commands.
