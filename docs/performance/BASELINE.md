# Backend performance baseline

Measured locally on 2026-10-19 using the canonical Docker Compose stack and
PostgreSQL, with the API and queue worker in their project containers. The
benchmark fixture contains 50,000 published X-S20 recipes and a single author;
requests are made from inside the API container. This is a repeatable
development baseline, not a production service-level objective.

## Results

| Operation | Requests | p50 | p95 | Database queries | Database time p50 / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `GET /api/v1/recipes?feed=popular&per_page=20` before index | 100 | 48.35 ms | 51.16 ms | 9 | 41.00 / 42.82 ms |
| `GET /api/v1/recipes/{id}` before index | 100 | 15.83 ms | 16.74 ms | 10 | 4.68 / 5.25 ms |
| `GET /api/v1/recipes?feed=popular&per_page=20` after index | 100 | 28.89 ms | 30.31 ms | 9 | 21.92 / 22.88 ms |
| `GET /api/v1/recipes/{id}` after index | 100 | 15.07 ms | 15.74 ms | 10 | 4.64 / 4.93 ms |

| Queue operation | Jobs | Queue wait p50 / p95 | Runtime p50 / p95 | Database queries | Database time p50 / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `GenerateRecipeImageDerivatives` (3200 × 2400 JPEG) | 20 | 4057.86 / 5555.82 ms | 155.35 / 221.71 ms | 2 | 1.03 / 1.22 ms |

Results are recorded from container-to-container HTTP requests after 10 warm-up
requests. Percentiles use nearest-rank ordering. API request logs provide query
counts and summed database execution time for each sample; total HTTP duration
includes application and response serialization time. The before-index query
plan scanned 50,000 recipe rows and used a top-N heapsort; execution took
19.336 ms. The detail lookup used `recipes_pkey` with an index-only scan and
executed in 0.028 ms.

## Query-plan and index review

The recipe list eagerly loads camera, author profile, categories, tags,
settings, and images in bounded relation queries, then paginates. Detail loads
the same relations for one recipe. Existing indexes cover `(camera_model_id,
status, published_at)`, `(user_id, status, updated_at)`, image lookup by
`(recipe_id, processing_status)`, and the relationship join keys. Popular
ordering uses a weighted expression over denormalized engagement counters.
The baseline plan required a full scan and top-N sort and took 19.336 ms. The
partial expression index for visible published recipes uses the exact ranking
order; the post-migration plan scanned the index for the first page and took
0.091 ms. The detail lookup used `recipes_pkey` both before and after
(0.028 ms and 0.025 ms). Recheck plans with production-sized data before
changing the ranking contract.

## Image processing

The derivative job decodes and orients each source image once, then produces
the configured larger derivative before scaling the same decoded image down
for smaller variants. Queue timing logs capture processing duration and
database work. The original is retained and sanitized derivative behavior is
covered by `RecipeImageStorageTest`.

## Reproduce

1. Start the canonical stack with the ignored local `docker/.env` file and run
   `php artisan db:seed --force` inside `api`.
2. Create 50,000 published X-S20 recipes for one active user, with distinct
   `published_at` timestamps and varied engagement counters.
3. Make 10 warm-ups and 100 measured container-to-container HTTP requests for
   the popular feed and one recipe detail endpoint. Use nearest-rank percentiles.
4. Read the `api.request.completed` events from the API container logs. The
   `feed` label distinguishes `popular` from `newest`; compare request time,
   query count, and summed database time.
5. Queue 20 derivative jobs from 3200 × 2400 JPEG originals. Read
   `queue.job.completed` events from the queue container logs for queue wait,
   runtime, and database timing.
6. Run `ANALYZE recipes`, then capture `EXPLAIN (ANALYZE, BUFFERS)` for the
   weighted popularity query and the primary-key detail lookup. Keep fixture
   size and container configuration with every comparison.
