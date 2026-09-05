# Deployment support

Deployment-specific assets and documentation belong in this directory.

The project has one root-level `docker-compose.yml` for the Coolify deployment.
Do not add a second Compose file or expose PostgreSQL or Redis publicly.

## Local stack

Create a local environment file from the committed example and replace the
placeholder database password:

    cp .env.example .env
    docker compose up -d

The API is available on the port configured by API_PORT, defaulting to 8000.
The API container runs database migrations before it becomes healthy. The
queue and scheduler wait for that healthy API container and use the same
application image and environment configuration.

Use docker compose ps and docker compose logs to inspect the stack. Stop it
with docker compose down; named PostgreSQL and Redis volumes are retained.

## Coolify deployment

Configure the repository as a Docker Compose application in Coolify and select
the root-level docker-compose.yml. Provide all deployment values as Coolify
runtime environment variables, including APP_KEY, DB_PASSWORD, and any
S3-compatible storage or Apple authentication values. Do not commit the
resulting .env file.

Route only the api service to the public domain on container port 8000.
The queue and scheduler are worker services, while PostgreSQL and Redis have no
published ports and must remain private to the Compose network. Attach
persistent volumes to postgres_data and redis_data.
