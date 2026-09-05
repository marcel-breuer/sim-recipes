# SimRecipes Laravel API

This directory contains the Laravel REST API. Public application endpoints are
versioned under `/api/v1`; PostgreSQL is the primary database and Redis handles
queues and cache. The Dockerfile packages the API for local and Coolify
deployment; the root Compose definition will be added with the deployment
foundation issue.

The Laravel application will be added in the backend foundation issue. Keep
deployment-specific configuration in the runtime environment and use the
provided `.env.example` as a local configuration reference.
