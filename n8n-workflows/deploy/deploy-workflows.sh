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
for file in "$WORKFLOWS_DIR"/*.json; do
  [ -e "$file" ] || continue
  
  workflow_name=$(jq -r '.name' "$file")
  echo "Processing workflow: $workflow_name"
  
  # Transform workflow JSON to only include API-compatible fields
  # Accepted fields: name, nodes, connections, settings, staticData, pinData, shared
  # Remove: active (read-only), versionId, meta, id, tags (internal/additional properties)
  transformed=$(jq '{
    name: .name,
    nodes: .nodes,
    connections: .connections,
    settings: (.settings // {executionOrder: "v1"}),
    staticData: (.staticData // null),
    pinData: (.pinData // {}),
    shared: (.shared // [])
  }' "$file")
  
  # Check if workflow already exists by name
  echo "Checking if workflow '$workflow_name' exists..."
  existing_workflow=$(curl -sS -X GET "${N8N_HOST%/}/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" | jq -r --arg name "$workflow_name" '.data[] | select(.name == $name) | .id')
  
  if [ -n "$existing_workflow" ]; then
    # Update existing workflow
    echo "Workflow exists (ID: $existing_workflow), updating..."
    url="${N8N_HOST%/}/api/v1/workflows/$existing_workflow"
    http_code=$(echo "$transformed" | curl -sS -w "%{http_code}" -X PUT "$url" \
      -H "Content-Type: application/json" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      --data-binary @- 2>&1)
    
    response_code="${http_code: -3}"
    if [ "$response_code" = "200" ] || [ "$response_code" = "201" ]; then
      echo "✓ Updated workflow '$workflow_name' (HTTP $response_code)"
    else
      echo "✗ Failed to update workflow '$workflow_name'. Response: ${http_code}" >&2
      failures=$((failures+1))
    fi
  else
    # Create new workflow
    echo "Workflow does not exist, creating new..."
    url="${N8N_HOST%/}/api/v1/workflows"
    http_code=$(echo "$transformed" | curl -sS -w "%{http_code}" -X POST "$url" \
      -H "Content-Type: application/json" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      --data-binary @- 2>&1)
    
    response_code="${http_code: -3}"
    if [ "$response_code" = "200" ] || [ "$response_code" = "201" ]; then
      echo "✓ Created workflow '$workflow_name' (HTTP $response_code)"
    else
      echo "✗ Failed to create workflow '$workflow_name'. Response: ${http_code}" >&2
      failures=$((failures+1))
    fi
  fi
  echo ""
done

if [ "$failures" -ne 0 ]; then
  echo "Deployment completed with $failures failures" >&2
  exit 2
fi

echo "All workflows deployed successfully"
