#!/usr/bin/env bash
set -e

WORKFLOW_FILE=$1
N8N_URL=$N8N_BASE_URL
API_KEY=$N8N_API_KEY
PROJECT_ID=$N8N_PROJECT_ID

NAME=$(jq -r '.name' "$WORKFLOW_FILE")

echo "Deploying workflow: $NAME"

# Find existing workflow by name
EXISTING_ID=$(curl -s "$N8N_URL/api/v1/workflows" \
  -H "Authorization: Bearer $API_KEY" |
  jq -r --arg NAME "$NAME" '.data[] | select(.name==$NAME) | .id')

if [ -z "$EXISTING_ID" ]; then
  echo "Creating workflow..."
  curl -s -X POST "$N8N_URL/api/v1/workflows" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq --arg pid "$PROJECT_ID" '. + {projectId:$pid}' "$WORKFLOW_FILE")"
else
  echo "Updating workflow ID $EXISTING_ID..."
  curl -s -X PUT "$N8N_URL/api/v1/workflows/$EXISTING_ID" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq '. + {id:null}' "$WORKFLOW_FILE")"
fi
