#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Validating n8n Workflows"
echo "=========================================="

WORKFLOWS_DIR="n8n-workflows/workflows"
ERRORS=0

# Find all JSON files
for WORKFLOW_FILE in $(find "$WORKFLOWS_DIR" -name "*.json"); do
  echo ""
  echo "Checking: $(basename "$WORKFLOW_FILE")"
  
  # Validate JSON syntax
  if ! jq empty "$WORKFLOW_FILE" 2>/dev/null; then
    echo "  ✗ Invalid JSON syntax"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  # Check required fields
  NAME=$(jq -r '.name // empty' "$WORKFLOW_FILE")
  NODES_COUNT=$(jq '.nodes | length' "$WORKFLOW_FILE")
  ACTIVE=$(jq -r '.active // false' "$WORKFLOW_FILE")
  
  if [ -z "$NAME" ]; then
    echo "  ✗ Missing 'name' field"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  if [ "$NODES_COUNT" = "0" ] || [ "$NODES_COUNT" = "null" ]; then
    echo "  ⚠ Warning: No nodes defined (empty workflow)"
  fi
  
  # Check for HTTP Request nodes with correct typeVersion
  HTTP_NODES=$(jq '[.nodes[] | select(.type == "n8n-nodes-base.httpRequest")] | length' "$WORKFLOW_FILE")
  if [ "$HTTP_NODES" -gt 0 ]; then
    WRONG_VERSION=$(jq '[.nodes[] | select(.type == "n8n-nodes-base.httpRequest" and .typeVersion != 2)] | length' "$WORKFLOW_FILE")
    if [ "$WRONG_VERSION" -gt 0 ]; then
      echo "  ✗ HTTP Request node(s) have wrong typeVersion (expected: 2)"
      ERRORS=$((ERRORS + 1))
      continue
    fi
    
    # Check for correct body parameters
    WRONG_PARAMS=$(jq '[.nodes[] | select(.type == "n8n-nodes-base.httpRequest" and .parameters.method == "POST" and (.parameters.bodyContentType == null or .parameters.jsonBody == null))] | length' "$WORKFLOW_FILE")
    if [ "$WRONG_PARAMS" -gt 0 ]; then
      echo "  ✗ HTTP Request POST node(s) missing bodyContentType or jsonBody"
      ERRORS=$((ERRORS + 1))
      continue
    fi
  fi
  
  echo "  ✓ Valid"
  echo "    Name: $NAME"
  echo "    Nodes: $NODES_COUNT"
  echo "    Active: $ACTIVE"
done

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
  echo "✓ All workflows validated successfully!"
  exit 0
else
  echo "✗ Found $ERRORS error(s)"
  exit 1
fi
