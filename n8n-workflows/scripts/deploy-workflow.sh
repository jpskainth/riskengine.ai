#!/usr/bin/env bash
set -e

WORKFLOW_FILE=$1
N8N_URL=$N8N_BASE_URL
API_KEY=$N8N_API_KEY
PROJECT_ID=$N8N_PROJECT_ID

if [ -z "$WORKFLOW_FILE" ] || [ ! -f "$WORKFLOW_FILE" ]; then
  echo "Error: Workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

if [ -z "$N8N_URL" ] || [ -z "$API_KEY" ]; then
  echo "Error: N8N_BASE_URL/N8N_HOST and N8N_API_KEY must be set" >&2
  exit 1
fi

NAME=$(jq -r '.name' "$WORKFLOW_FILE")

echo "Deploying workflow: $NAME"

# Transform workflow to API-compatible format
TRANSFORMED=$(jq '{
  name: .name,
  nodes: .nodes,
  connections: .connections,
  settings: (.settings // {executionOrder: "v1"}),
  staticData: (.staticData // null),
  pinData: (.pinData // {}),
  shared: (.shared // [])
}' "$WORKFLOW_FILE")

# Find existing workflow by name
WORKFLOWS_RESPONSE=$(curl -sS "$N8N_URL/api/v1/workflows" \
  -H "X-N8N-API-KEY: $API_KEY")

# Check if response is valid JSON
if ! echo "$WORKFLOWS_RESPONSE" | jq empty 2>/dev/null; then
  echo "Error: Failed to fetch workflows. API response:" >&2
  echo "$WORKFLOWS_RESPONSE" >&2
  exit 1
fi

EXISTING_ID=$(echo "$WORKFLOWS_RESPONSE" | jq -r --arg NAME "$NAME" '.data[]? | select(.name==$NAME) | .id')

if [ -z "$EXISTING_ID" ]; then
  echo "Creating new workflow..."
  RESPONSE=$(echo "$TRANSFORMED" | curl -sS -X POST "$N8N_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  
  if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✓ Created workflow successfully"
  else
    echo "✗ Failed to create workflow: $RESPONSE" >&2
    exit 1
  fi
else
  echo "Updating existing workflow (ID: $EXISTING_ID)..."
  RESPONSE=$(echo "$TRANSFORMED" | curl -sS -X PUT "$N8N_URL/api/v1/workflows/$EXISTING_ID" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  
  if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✓ Updated workflow successfully"
  else
    echo "✗ Failed to update workflow: $RESPONSE" >&2
    exit 1
  fi
fi
