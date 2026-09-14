# Operations and recovery

SimRecipes keeps PostgreSQL data, Redis state, and uploaded image files in
separate persistent volumes. Backups must cover PostgreSQL and `storage_data`;
Redis is rebuildable queue/cache state and should not be treated as the source
of truth.

## Backup

Run a PostgreSQL logical backup from the Compose network using a protected
destination outside the repository:

```sh
docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml exec -T postgres \
  sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' \
  > sim-recipes-$(date +%Y%m%d).dump
```

The `storage_data` volume must be copied with a volume-aware backup process or
by mounting it into a temporary container. Do not expose PostgreSQL or Redis
ports to perform backups.

## Restore rehearsal

Restore into an isolated database and volume before replacing production data:

```sh
docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml exec -T postgres \
  sh -lc 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' < backup.dump
docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml exec api php artisan migrate:status
docker compose --project-directory . --env-file docker/.env -f docker/docker-compose.yml exec api php artisan storage:link
```

After restore, verify `/api/v1/health/ready`, a public recipe, a private image
authorization check, and an image stored before the restore. Never run the
restore rehearsal against production credentials or the live database.

## Observability

Every response includes an `X-Request-ID`. A valid incoming request ID is
preserved; otherwise the API generates a UUID and adds it to the application
log context. The readiness endpoint checks PostgreSQL and Redis independently
and returns HTTP 503 when either dependency is unavailable.
