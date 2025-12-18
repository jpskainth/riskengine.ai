#!/usr/bin/env bash
set -euo pipefail

if [ -z "${N8N_HOST:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
  echo "Environment variables N8N_HOST and N8N_API_KEY are required" >&2
  exit 1
fi

WORKFLOWS_DIR="$(dirname "$0")/../workflows"
WORKFLOWS_DIR=$(realpath "$WORKFLOWS_DIR")

if [ ! -d "$WORKFLOWS_DIR" ]; then
  echo "Workflows directory not found: $WORKFLOWS_DIR" >&2
  exit 1
fi

failures=0
for file in "$WORKFLOWS_DIR"/*.json; do
  [ -e "$file" ] || continue
  echo "Deploying $file"
  success=0
  for endpoint in "/rest/workflows/import" "/workflows/import" "/workflows"; do
    url="${N8N_HOST%/}$endpoint"
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$url" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $N8N_API_KEY" \
      --data-binary @"$file" || true)
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
      echo "Deployed $file to $url (HTTP $http_code)"
      success=1
      break
    else
      echo "Attempt to $url returned HTTP $http_code"
    fi
  done
  if [ "$success" -ne 1 ]; then
    echo "Failed to deploy $file" >&2
    failures=$((failures+1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "Deployment completed with $failures failures" >&2
  exit 2
fi

echo "All workflows deployed successfully"
