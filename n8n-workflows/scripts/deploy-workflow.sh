#!/usr/bin/env bash
set -e

WORKFLOW_FILE=$1
N8N_URL=${N8N_BASE_URL:-$N8N_HOST}
MCP_BEARER_TOKEN=${MCP_BEARER_TOKEN:-$N8N_MCP_BEARER_TOKEN}
PROJECT_ID=${N8N_PROJECT_ID:-44VO5JoWTqmtzM1F}

echo "==========================================="
echo "Processing file: $WORKFLOW_FILE"
echo "==========================================="

if [ -z "$WORKFLOW_FILE" ] || [ ! -f "$WORKFLOW_FILE" ]; then
  echo "Error: Workflow file not found: $WORKFLOW_FILE" >&2
  exit 1
fi

# Check if file is valid JSON
if ! jq empty "$WORKFLOW_FILE" 2>/dev/null; then
  echo "⚠ Skipping invalid JSON file: $WORKFLOW_FILE"
  exit 0
fi

# Check if file has no nodes
NODES_COUNT=$(jq '.nodes | length' "$WORKFLOW_FILE" 2>/dev/null)
if [ -z "$NODES_COUNT" ] || [ "$NODES_COUNT" = "0" ] || [ "$NODES_COUNT" = "null" ]; then
  echo "⚠ Skipping workflow with no nodes: $WORKFLOW_FILE"
  exit 0
fi


# Check for required auth based on endpoint
if [[ "$N8N_URL" == *mcp-server* ]] || [[ "$N8N_URL" == *mcp* ]]; then
  if [ -z "$N8N_URL" ] || [ -z "$MCP_BEARER_TOKEN" ]; then
    echo "Error: N8N_BASE_URL/N8N_HOST and MCP_BEARER_TOKEN must be set for MCP deployment" >&2
    exit 1
  fi
else
  if [ -z "$N8N_URL" ] || [ -z "$API_KEY" ]; then
    echo "Error: N8N_BASE_URL/N8N_HOST and N8N_API_KEY must be set for standard n8n deployment" >&2
    exit 1
  fi
fi


# Remove trailing slash from URL
N8N_URL="${N8N_URL%/}"

# Use MCP endpoint if specified
if [[ "$N8N_URL" == *mcp-server* ]]; then
  API_URL="$N8N_URL"
else
  API_URL="$N8N_URL/mcp-server/http"
fi

NAME=$(jq -r '.name' "$WORKFLOW_FILE")
echo "Deploying workflow: $NAME"

# Transform workflow to API-compatible format
# Per n8n Public API v1 spec (additionalProperties: false):
# Required: name, nodes, connections, settings
# Optional: staticData, shared
# NOT SUPPORTED: pinData (not in API schema)
# Read-only (auto-removed): id, active, createdAt, updatedAt, tags, activeVersion, versionId
TRANSFORMED=$(jq '{
  name: .name,
  nodes: .nodes,
  connections: (.connections // {}),
  settings: (.settings // {executionOrder: "v1"})
} + (if .staticData != null then {staticData: .staticData} else {} end)
  + (if .shared != null and (.shared | length > 0) then {shared: .shared} else {} end)' "$WORKFLOW_FILE")


# Find existing workflow by name (MCP)
echo "Checking for existing workflow..."
WORKFLOWS_RESPONSE=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" "$API_URL/workflows?name=$(jq -rn --arg n "$NAME" '$n|@uri')" \
  -H "Authorization: Bearer $MCP_BEARER_TOKEN")

HTTP_STATUS=$(echo "$WORKFLOWS_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$WORKFLOWS_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Error: API returned HTTP $HTTP_STATUS" >&2
  echo "URL: $N8N_URL/api/v1/workflows" >&2
  echo "Response: $RESPONSE_BODY" | head -n 10 >&2
  exit 1
fi

# Check if response is valid JSON
if ! echo "$RESPONSE_BODY" | jq empty 2>/dev/null; then
  echo "Error: API returned non-JSON response." >&2
  echo "This usually means the URL is incorrect or points to the n8n UI instead of the API." >&2
  echo "Expected URL format: http://host:port (without /api/v1)" >&2
  echo "Current URL: $N8N_URL" >&2
  exit 1
fi

EXISTING_ID=$(echo "$RESPONSE_BODY" | jq -r --arg NAME "$NAME" '.data[]? | select(.name==$NAME) | .id' | head -n 1)

if [ -z "$EXISTING_ID" ]; then
  echo "Creating new workflow..."
  CREATE_RESPONSE=$(echo "$TRANSFORMED" | curl -sS -w "\nHTTP_STATUS:%{http_code}" -X POST "$API_URL/workflows" \
    -H "Authorization: Bearer $MCP_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  
  CREATE_STATUS=$(echo "$CREATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  CREATE_BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_STATUS:/d')
  
  if [ "$CREATE_STATUS" = "200" ] || [ "$CREATE_STATUS" = "201" ]; then
    WORKFLOW_ID=$(echo "$CREATE_BODY" | jq -r '.id')
    echo "✓ Created workflow successfully (ID: $WORKFLOW_ID)"
  else
    echo "✗ Failed to create workflow (HTTP $CREATE_STATUS)" >&2
    echo "$CREATE_BODY" | jq '.' 2>/dev/null || echo "$CREATE_BODY" >&2
    exit 1
  fi
else
  echo "Updating existing workflow (ID: $EXISTING_ID)..."
  UPDATE_RESPONSE=$(echo "$TRANSFORMED" | curl -sS -w "\nHTTP_STATUS:%{http_code}" -X PUT "$API_URL/workflows/$EXISTING_ID" \
    -H "Authorization: Bearer $MCP_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @-)
  
  UPDATE_STATUS=$(echo "$UPDATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  UPDATE_BODY=$(echo "$UPDATE_RESPONSE" | sed '/HTTP_STATUS:/d')
  
  if [ "$UPDATE_STATUS" = "200" ]; then
    echo "✓ Updated workflow successfully"
  else
    echo "✗ Failed to update workflow (HTTP $UPDATE_STATUS)" >&2
    echo "$UPDATE_BODY" | jq '.' 2>/dev/null || echo "$UPDATE_BODY" >&2
    exit 1
  fi
  WORKFLOW_ID=$EXISTING_ID
fi

# Activate workflow if marked as active in JSON
SHOULD_ACTIVATE=$(jq -r '.active // false' "$WORKFLOW_FILE")
if [ "$SHOULD_ACTIVATE" = "true" ]; then
  echo "Activating workflow..."
  ACTIVATE_RESPONSE=$(curl -sS -w "\nHTTP_STATUS:%{http_code}" -X POST "$API_URL/workflows/$WORKFLOW_ID/activate" \
    -H "Authorization: Bearer $MCP_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}')
  
  ACTIVATE_STATUS=$(echo "$ACTIVATE_RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
  ACTIVATE_BODY=$(echo "$ACTIVATE_RESPONSE" | sed '/HTTP_STATUS:/d')
  
  if [ "$ACTIVATE_STATUS" = "200" ]; then
    echo "✓ Activated workflow successfully"
  else
    echo "⚠ Failed to activate workflow (HTTP $ACTIVATE_STATUS)"
    echo "$ACTIVATE_BODY" | jq '.' 2>/dev/null || echo "$ACTIVATE_BODY" >&2
  fi
fi
