#!/usr/bin/env bash
set -euo pipefail
REQ=${REQ:-$(uuidgen || echo test)}
URL=${URL:-http://localhost:3000/up}
out=$(curl -fsS -H "X-Request-ID: $REQ" "$URL" || true)
echo "$out" | grep -qi "ok" && { echo "smoke ok ($REQ)"; exit 0; } || { echo "smoke failed ($REQ)"; exit 1; }