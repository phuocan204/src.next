#!/usr/bin/env bash
set -euo pipefail

: "${DISCORD_WEBHOOK_URL:?DISCORD_WEBHOOK_URL is required}"
: "${DISCORD_MESSAGE:?DISCORD_MESSAGE is required}"

payload="$({
  printf '%s' "${DISCORD_MESSAGE}" | python3 -c \
    'import json, sys; print(json.dumps({"content": sys.stdin.read()}))'
})"

curl --fail-with-body --silent --show-error --retry 3 \
  -H 'Content-Type: application/json' \
  --data "${payload}" \
  "${DISCORD_WEBHOOK_URL}"
