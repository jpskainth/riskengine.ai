# Pre-Deployment Checklist

## Before Pushing to Repository

### 1. Validate All Workflows
```powershell
cd "c:\Users\jaspal.singh\Documents\Personal Projects\riskengine.ai-1"

# Check all source workflows
Get-ChildItem "n8n-workflows\workflows\sources" -Filter "*.json" | ForEach-Object { 
    $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
    $httpNodes = $content.nodes | Where-Object { $_.type -eq "n8n-nodes-base.httpRequest" -and $_.parameters.method -eq "POST" }
    if ($httpNodes) {
        $valid = $httpNodes | Where-Object { $_.typeVersion -eq 2 -and $_.parameters.bodyContentType -eq 'application/json' }
        if ($valid.Count -eq $httpNodes.Count) {
            Write-Host "✓ $($_.Name)" -ForegroundColor Green
        } else {
            Write-Host "✗ $($_.Name) - Invalid HTTP Request config" -ForegroundColor Red
        }
    }
}
```

### 2. Verify Required Fields
- ✅ All workflows have `"active": true`
- ✅ All HTTP Request nodes use typeVersion 2
- ✅ All HTTP Request POST nodes have:
  - `"method": "POST"`
  - `"bodyContentType": "application/json"`
  - `"jsonBody": "={{ JSON.stringify($json) }}"`

### 3. Check GitHub Secrets
Ensure these secrets are set in GitHub repository settings:
- `N8N_HOST`: `http://192.9.170.179:5678`
- `N8N_API_KEY`: Your n8n API key
- `N8N_PROJECT_ID`: Your n8n project ID (optional)

### 4. Test Locally (Optional)
```bash
# Test single workflow deployment
export N8N_BASE_URL="http://192.9.170.179:5678"
export N8N_API_KEY="your-api-key"
bash n8n-workflows/scripts/deploy-workflow.sh n8n-workflows/workflows/core/wf-risk-sink.json
```

### 5. Commit and Push
```bash
git add .
git commit -m "Fix: Standardize HTTP Request nodes for n8n 1.123.5"
git push origin main
```

### 6. Monitor GitHub Actions
- Go to repository → Actions tab
- Watch deployment progress
- Check for any errors

### 7. Verify in n8n
After deployment:
1. Open n8n UI: http://192.9.170.179:5678
2. Verify workflows are imported
3. Check workflow status (should be Active)
4. Test webhook endpoint:
```bash
curl -X POST http://192.9.170.179:5678/webhook/risk-sink \
  -H "Content-Type: application/json" \
  -d '{"risk_type":"test","severity":0.5,"source":"TEST","text":"test"}'
```

## Common Issues and Solutions

### Issue: Workflow not activating
**Solution:** Ensure `"active": true` in JSON, deploy script will call activate endpoint

### Issue: HTTP Request not sending body
**Solution:** Verify exact parameters match:
```json
{
  "method": "POST",
  "bodyContentType": "application/json",
  "jsonBody": "={{ JSON.stringify($json) }}"
}
```

### Issue: 404 webhook not found
**Solution:** wf-risk-sink.json must be deployed and active first

### Issue: Deployment script fails
**Solution:** Check N8N_HOST format (no trailing slash, no /api/v1 path)

## Deployment Order
For first-time deployment, deploy in this order:
1. wf-risk-sink.json (webhook endpoint)
2. wf-risk-outbox-processor.json (processor)
3. All source workflows (ingesters)

## Success Criteria
- ✅ All workflows show as "Active" in n8n UI
- ✅ Webhook endpoint responds with 200 OK
- ✅ Test data appears in risk_outbox table
- ✅ Processor runs and moves data to risk_events table
