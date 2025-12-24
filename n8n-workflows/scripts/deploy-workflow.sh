#!/usr/bin/env bash
set -e

WORKFLOW_FILE=$1
N8N_URL=${N8N_BASE_URL:-$N8N_HOST}
API_KEY=$N8N_API_KEY
PROJECT_ID=${N8N_PROJECT_ID:-44VO5JoWTqmtzM1F}

if [ -z "$WORKFLOW_FILE" ] || [ ! -f "$WORKFLOW_FILE" ]; then
  echo "Error: Workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

if [ -z "$N8N_URL" ] || [ -z "$API_KEY" ]; then
  echo "Error: N8N_BASE_URL/N8N_HOST and N8N_API_KEY must be set" >&2
  exit 1
fi

# Remove trailing slash from URL
N8N_URL="${N8N_URL%/}"

echo "n8n URL: $N8N_URL"
echo "API Endpoint: $N8N_URL/api/v1/workflows"

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
echo "Fetching existing workflows..."
WORKFLOWS_RESPONSE=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" "$N8N_URL/api/v1/workflows" \
  -H "X-N8N-API-KEY: $API_KEY")

HTTP_STATUS=$(echo "$WORKFLOWS_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$WORKFLOWS_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Error: API returned HTTP $HTTP_STATUS" >&2
  echo "Response: $RESPONSE_BODY" >&2
  exit 1
fi

# Check if response is valid JSON
if ! echo "$RESPONSE_BODY" | jq empty 2>/dev/null; then
  echo "Error: API returned non-JSON response (likely HTML). Check your URL and ensure it points to the n8n API." >&2
  echo "Expected: http://your-n8n-host:port" >&2
  echo "Got response starting with: $(echo "$RESPONSE_BODY" | head -n 5)" >&2
  exit 1
fi

EXISTING_ID=$(echo "$RESPONSE_BODY" | jq -r --arg NAME "$NAME" '.data[]? | select(.name==$NAME) | .id')

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
