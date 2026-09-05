# SimRecipes Laravel API

This directory contains the Laravel REST API. Public application endpoints are
versioned under `/api/v1`; PostgreSQL is the primary database and Redis handles
queues and cache. The Dockerfile packages the API for local and Coolify
deployment; the root Compose definition will be added with the deployment
foundation issue.

Keep deployment-specific configuration in the runtime environment and use the
provided `.env.example` as a local configuration reference.

The authentication boundary is available under `/api/v1/auth`: Apple identity
tokens are verified server-side, and authenticated clients receive expiring
Laravel Sanctum bearer tokens. Apple credentials and token values are never
logged or returned after the login response.
