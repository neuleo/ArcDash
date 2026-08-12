#!/usr/bin/env bash
set -e

echo "==> Running format, analyze, and test via Docker..."
docker compose run --rm flutter dart format lib test
docker compose run --rm flutter flutter test
echo "==> Rebuild & verification completed successfully!"
