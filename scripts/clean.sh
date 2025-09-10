#!/usr/bin/env bash
set -euo pipefail
bin/rails db:drop db:create db:migrate 2>/dev/null || true
docker compose down -v 2>/dev/null || true
