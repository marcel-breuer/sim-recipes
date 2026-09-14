# Deployment support

Deployment-specific assets and documentation belong in this directory.

The canonical deployment file is `docker/docker-compose.yml`. It builds the API
from `docker/Dockerfile`, which extends Server Side Up's `serversideup/php`
8.4 FPM/NGINX image. Do not expose PostgreSQL or Redis publicly.

## Local stack

Create a local environment file from the committed example and replace the
placeholder secrets:

    cp docker/.env.example docker/.env
    docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml up -d --build

The API listens on container port `8080`. For local host access, publish that
port explicitly in your local Compose setup; production Coolify deployments
must route the `api` domain to internal port `8080` without publishing a host
port.
The API container runs Laravel migrations through Server Side Up's autorun
configuration before it becomes healthy. The queue and scheduler wait for that
healthy API container and use the same application image.

Seed the X-S20 camera catalog explicitly on a new database:

    docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml \
        exec api php artisan db:seed --force

Use `docker compose ps` and `docker compose logs` to inspect the stack. Stop it
with `docker compose down`; named PostgreSQL and Redis volumes are retained.

## Coolify deployment

Configure the repository as a Docker Compose application in Coolify and select
the repository root (`/`) as the Base Directory and
`docker/docker-compose.yml` as the Docker Compose Location. The build context
must remain the repository root because `docker/Dockerfile` copies the Laravel
application from `backend/`. Import the variable names from
`docker/.env.example` and provide production values as Coolify runtime
environment variables, including `APP_KEY` and database/Redis passwords. Image
uploads use the `storage_data` persistent volume through Laravel's local disk.
Set `AUTORUN_LARAVEL_MIGRATION_SEED=true`
for the first deployment only, then set it back to `false`. Do not commit the
resulting `.env` file.

Route only the `api` service to the public domain on container port 8080. In
Coolify, enter the domain for the `api` service with the internal port, for
example `https://api.example.com:8080`; this selects the container port and
does not bind port 8080 on the host.
The queue and scheduler are worker services, while PostgreSQL and Redis have no
published ports and must remain private to the Compose network. Attach
persistent volumes to postgres_data, redis_data, and storage_data. The API,
queue, and scheduler share storage_data so uploads and image derivatives are
available to every application process.

The API image uses Server Side Up's unprivileged `www-data` runtime, PHP 8.4,
NGINX, PHP-FPM, Composer, PostgreSQL, GD, and Redis extensions. The queue and
scheduler use the same application image with dedicated Artisan commands.
