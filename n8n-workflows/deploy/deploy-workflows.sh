#!/usr/bin/env bash
set -euo pipefail

if [ -z "${N8N_HOST:-}" ] || [ -z "${N8N_API_KEY:-}" ]; then
  echo "Environment variables N8N_HOST and N8N_API_KEY are required" >&2
  exit 1
fi

WORKFLOWS_DIR="$(dirname "$0")/../workflows"
WORKFLOWS_DIR=$(realpath "$WORKFLOWS_DIR")

if [ ! -d "$WORKFLOWS_DIR" ]; then
  echo "Workflows directory not found, creating: $WORKFLOWS_DIR"
  mkdir -p "$WORKFLOWS_DIR"
fi

# If there are no workflow files, exit cleanly
has_files=0
for f in "$WORKFLOWS_DIR"/*.json; do
  [ -e "$f" ] && { has_files=1; break; }
done
if [ "$has_files" -eq 0 ]; then
  echo "No workflow JSON files found in $WORKFLOWS_DIR; nothing to deploy."
  exit 0
fi

failures=0
for file in "$WORKFLOWS_DIR"/.json; do
  [ -e "$file" ] || continue
  echo "Deploying $file"
  url="${N8N_HOST%/}/api/v1/workflows"
  
  # Transform workflow JSON to only include API-compatible fields
  # Accepted fields: name, nodes, connections, settings, staticData, pinData
  # Remove: active (read-only), versionId, meta, id, tags, shared (internal/additional properties)
  transformed=$(jq '{
    name: .name,
    nodes: .nodes,
    connections: .connections,
    settings: (.settings // {executionOrder: "v1"}),
    staticData: (.staticData // {}),
    pinData: (.pinData // {})
  }' "$file")
  
  http_code=$(echo "$transformed" | curl -sS -w "%{http_code}" -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    --data-binary @- 2>&1)
  
  response_code="${http_code: -3}"
  if [ "$response_code" = "200" ] || [ "$response_code" = "201" ]; then
    echo "Deployed $file to $url (HTTP $response_code)"
  else
    echo "Failed to deploy $file to $url. Response: ${http_code}" >&2
    failures=$((failures+1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "Deployment completed with $failures failures" >&2
  exit 2
fi

echo "All workflows deployed successfully"
