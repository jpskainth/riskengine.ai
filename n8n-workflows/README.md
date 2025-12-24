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
n8n-workflows/
├── workflows/               # Workflow JSON files
│   ├── wf-01-risk-ingestion.json
│   ├── wf-02-booking-ingestion.json
│   ├── wf-03-matching-engine.json
│   ├── wf-04-policy-engine.json
│   └── wf-05-action-engine.json
├── credentials/            # Credential configurations (not deployed)
├── deploy/                 # Deployment scripts
│   └── deploy-workflows.sh
└── env/                    # Environment configurations
    ├── dev.env
    ├── staging.env
    └── prod.env
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

### Required Fields

- `name` - Unique workflow name (used for matching during updates)
- `nodes` - Array of workflow nodes
- `connections` - Node connections object
- `settings` - Workflow settings (must include `executionOrder`)
- `staticData` - Static data (can be `null`)
- `pinData` - Pinned data object
- `shared` - Sharing configuration with role and projectId

### Fields Automatically Removed

The deploy script removes these fields as they are read-only or auto-generated:
- `active` - Read-only field managed by n8n
- `id` - Auto-assigned by n8n
- `versionId` - Auto-assigned by n8n
- `meta` - Internal metadata
- `tags` - Managed separately
- `createdAt` / `updatedAt` - Auto-managed timestamps

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
# From project root
bash n8n-workflows/deploy/deploy-workflows.sh

# Or from deploy directory
cd n8n-workflows/deploy
./deploy-workflows.sh
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

Location: `.github/workflows/deploy-n8n.yml`

```yaml
name: Deploy n8n Workflows

on:
  push:
    branches: [main]
    paths:
      - 'n8n-workflows/workflows/**'
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      
      - name: Deploy workflows
        env:
          N8N_HOST: ${{ secrets.N8N_HOST }}
          N8N_API_KEY: ${{ secrets.N8N_API_KEY }}
        run: bash n8n-workflows/deploy/deploy-workflows.sh
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
4. Place in `workflows/` directory
5. Commit and push to trigger deployment

### Option 2: Create from Template

1. Copy an existing workflow JSON from `workflows/` directory
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

1. Modify the workflow JSON file in `workflows/` directory
2. Keep the `name` field unchanged (this is the matching key)
3. Update `nodes`, `connections`, or other fields as needed
4. Commit and push to trigger deployment

The script will:
- Look up the existing workflow by name
- Update it using the workflow's ID
- Preserve the workflow's activation status

## API Endpoints Used

- **GET** `/api/v1/workflows` - List all workflows (for matching)
- **POST** `/api/v1/workflows` - Create new workflow
- **PUT** `/api/v1/workflows/{id}` - Update existing workflow

## Authentication

Uses n8n Public API v1 with API Key authentication:
- Header: `X-N8N-API-KEY: your-api-key`
- No Bearer token required

## Troubleshooting

### Error: "must NOT have additional properties"

Your workflow JSON contains fields not accepted by the API. The deploy script automatically filters these out, but if you see this error, ensure you're using the latest version of `deploy-workflows.sh`.

### Error: "active is read-only"

Remove the `active` field from your workflow JSON. The deploy script handles this automatically.

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
- Workflow files are in `n8n-workflows/workflows/` directory
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
