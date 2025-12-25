# n8n Workflow CI/CD Pipeline

This CI/CD pipeline automates the deployment of n8n workflows to a self-hosted n8n instance. It supports both creating new workflows and updating existing ones.

## Features

- ✅ **Create new workflows** - Automatically creates workflows that don't exist
- ✅ **Update existing workflows** - Updates workflows based on workflow name matching
- ✅ **Idempotent deployments** - Safe to run multiple times
- ✅ **GitHub Actions integration** - Automatic deployment on push to main branch
- ✅ **Manual deployment** - Can be run locally via bash script

## Directory Structure

```
riskengine.ai-1/                     # Repository root
├── .github/                         # GitHub Actions workflows (repository root)
│   └── workflows/
│       └── deploy-n8n.yml
└── n8n-workflows/
    ├── workflows/                   # Workflow JSON files
    │   └── risk-engine/            # Project-specific workflows
    │       └── wf-01-risk-ingestion.json
    ├── scripts/                    # Deployment scripts
    │   └── deploy-workflow.sh
    ├── credentials/                # Credential configurations (not deployed)
    │   ├── sendgrid.json
    │   └── sqlserver.json
    ├── env/                        # Environment configurations
    │   ├── dev.env
    │   ├── staging.env
    │   └── prod.env
    └── README.md
```

## Workflow JSON Structure

Each workflow JSON file must follow this structure (compatible with n8n Public API v1):

```json
{
  "name": "RiskEngine.ai - wf-01-risk-ingestion",
  "nodes": [
    {
      "parameters": {},
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2.1,
      "position": [0, 0],
      "id": "unique-node-id",
      "name": "Node Name"
    }
  ],
  "connections": {},
  "settings": {
    "executionOrder": "v1"
  },
  "staticData": null,
  "pinData": {},
  "shared": [
    {
      "role": "workflow:owner",
      "projectId": "44VO5JoWTqmtzM1F"
    }
  ]
}
```

### Required Fields (per n8n Public API v1 Schema)

- `name` - Unique workflow name (used for matching during updates)
- `nodes` - Array of workflow nodes
- `connections` - Node connections object
- `settings` - Workflow settings object

### Optional Fields

- `staticData` - Static workflow data (object or null)
- `pinData` - Pinned test data object
- `shared` - Array of sharing configurations with role and projectId

### Read-Only Fields (Automatically Removed)

The deploy script automatically removes these fields before API submission:
- `id` - Auto-assigned by n8n
- `active` - Read-only, managed by n8n activation endpoints
- `versionId` / `activeVersionId` - Auto-assigned version tracking
- `createdAt` / `updatedAt` - Auto-managed timestamps
- `tags` - Managed via separate tags API
- `activeVersion` - Read-only version information

## Manual Deployment

### Prerequisites

1. **jq** - JSON processor (install via package manager)
2. **curl** - HTTP client (usually pre-installed)
3. **n8n API key** - Generate from n8n instance: Settings → API → Create API Key

### Environment Variables

Set these environment variables before running the script:

```bash
export N8N_HOST="http://192.9.170.179:5678"
export N8N_API_KEY="your-api-key-here"
```

### Run Deployment

```bash
# Deploy a single workflow
bash n8n-workflows/scripts/deploy-workflow.sh n8n-workflows/workflows/risk-engine/wf-01-risk-ingestion.json

# Deploy all workflows
for wf in n8n-workflows/workflows/**/*.json; do
  bash n8n-workflows/scripts/deploy-workflow.sh "$wf"
done
```

### Expected Output

```
Processing workflow: RiskEngine.ai - wf-01-risk-ingestion
Checking if workflow 'RiskEngine.ai - wf-01-risk-ingestion' exists...
Workflow does not exist, creating new...
✓ Created workflow 'RiskEngine.ai - wf-01-risk-ingestion' (HTTP 201)

Processing workflow: RiskEngine.ai - wf-02-booking-ingestion
Checking if workflow 'RiskEngine.ai - wf-02-booking-ingestion' exists...
Workflow exists (ID: abc123), updating...
✓ Updated workflow 'RiskEngine.ai - wf-02-booking-ingestion' (HTTP 200)

All workflows deployed successfully
```

## GitHub Actions Deployment

### Setup

1. **Add GitHub Secrets**:
   - Go to repository Settings → Secrets and variables → Actions
   - Add `N8N_HOST` (e.g., `http://192.9.170.179:5678`)
   - Add `N8N_API_KEY` (your n8n API key)

2. **Trigger Deployment**:
   - Push changes to `main` branch
   - Or manually trigger from Actions tab

### Workflow File

Location: `.github/workflows/deploy-n8n.yml` (repository root)

```yaml
name: Deploy n8n workflows

on:
  push:
    branches: [ main ]
    paths:
      - "n8n-workflows/workflows/**"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install jq
        run: sudo apt-get install -y jq
      
      - name: Deploy workflows
        env:
          N8N_BASE_URL: ${{ secrets.N8N_HOST }}
          N8N_API_KEY: ${{ secrets.N8N_API_KEY }}
          N8N_PROJECT_ID: ${{ secrets.N8N_PROJECT_ID }}
        run: |
          for wf in n8n-workflows/workflows/**/*.json; do
            bash n8n-workflows/scripts/deploy-workflow.sh "$wf"
          done
```

## Creating New Workflows

### Option 1: Export from n8n UI

1. Create workflow in n8n UI
2. Download workflow JSON
3. Clean the JSON:
   ```bash
   jq '{
     name: .name,
     nodes: .nodes,
     connections: .connections,
     settings: .settings,
     staticData: .staticData,
     pinData: .pinData,
     shared: .shared
   }' downloaded-workflow.json > wf-XX-new-workflow.json
   ```
4. Place in `workflows/risk-engine/` directory
5. Commit and push to trigger deployment

### Option 2: Create from Template

1. Copy an existing workflow JSON from `workflows/risk-engine/` directory
2. Update the following fields:
   - `name` - Give it a unique name
   - `nodes` - Add your nodes with unique IDs
   - `connections` - Define node connections
3. Commit and push

### Workflow Naming Convention

Use this pattern for consistency:
- `RiskEngine.ai - wf-XX-workflow-name`
- Example: `RiskEngine.ai - wf-06-reporting-engine`

## Updating Existing Workflows

1. Modify the workflow JSON file in `workflows/risk-engine/` directory
2. Keep the `name` field unchanged (this is the matching key)
3. Update `nodes`, `connections`, or other fields as needed
4. Commit and push to trigger deployment

The script will:
- Look up the existing workflow by name
- Update it using the workflow's ID
- Preserve the workflow's activation status

## API Endpoints Used

Based on n8n Public API v1 specification:

- **GET** `/api/v1/workflows?name={workflowName}` - Query workflows by name
- **POST** `/api/v1/workflows` - Create new workflow
- **PUT** `/api/v1/workflows/{id}` - Update existing workflow
- **POST** `/api/v1/workflows/{id}/activate` - Activate a workflow (optional)
- **POST** `/api/v1/workflows/{id}/deactivate` - Deactivate a workflow (optional)

## Authentication

n8n Public API v1 uses API Key authentication:
- **Header**: `X-N8N-API-KEY: your-api-key`
- **Not** `Authorization: Bearer`

Generate API key: n8n Settings → API → Create API Key

## Troubleshooting

### Error: HTML response instead of JSON

**Cause**: URL points to n8n UI instead of API endpoint

**Solution**: 
- ✅ Correct: `N8N_HOST=http://192.9.170.179:5678`
- ❌ Wrong: `N8N_HOST=http://192.9.170.179:5678/api/v1`

### Error: "must NOT have additional properties"

**Cause**: Workflow JSON contains fields not accepted by the API schema

**Solution**: The deploy script automatically filters out read-only fields. Accepted fields:
- Required: `name`, `nodes`, `connections`, `settings`
- Optional: `staticData`, `pinData`, `shared`

### Error: "active is read-only"

**Cause**: Trying to set `active` field via create/update endpoints

**Solution**: Use activation endpoints instead:
- `POST /api/v1/workflows/{id}/activate`
- `POST /api/v1/workflows/{id}/deactivate`

### Error: "must have required property 'settings'"

Add the `settings` object to your workflow:
```json
"settings": {
  "executionOrder": "v1"
}
```

### Workflow not updating

Ensure the `name` field matches exactly (case-sensitive). The script matches workflows by name to determine whether to create or update.

### No workflows found

Check that:
- Workflow files are in `n8n-workflows/workflows/risk-engine/` directory (or other project subdirectories)
- Files have `.json` extension
- Files contain valid JSON

## Security Best Practices

1. **Never commit API keys** to the repository
2. **Use GitHub Secrets** for sensitive values
3. **Rotate API keys** periodically
4. **Limit API key permissions** to workflow management only
5. **Review workflow changes** before deploying to production

## Project Configuration

- **n8n Instance**: http://192.9.170.179:5678
- **Project ID**: 44VO5JoWTqmtzM1F
- **Workflow Owner Role**: workflow:owner

## Future Enhancements

- [ ] Add workflow validation before deployment
- [ ] Support for credential deployment
- [ ] Environment-specific deployments (dev/staging/prod)
- [ ] Rollback capability
- [ ] Workflow testing automation
- [ ] Drift detection (compare local vs deployed)
