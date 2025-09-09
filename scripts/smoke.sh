#!/usr/bin/env bash
set -euo pipefail
REQ=${REQ:-$(uuidgen || echo test)}
URL=${URL:-http://localhost:3000/up}
out=$(curl -fsS -H "X-Request-ID: $REQ" "$URL" || true)
status=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Request-ID: $REQ" "$URL" || true)
[ "$status" = "200" ] && { echo "smoke ok ($REQ)"; exit 0; } || { echo "smoke failed ($REQ)"; exit 1; }

