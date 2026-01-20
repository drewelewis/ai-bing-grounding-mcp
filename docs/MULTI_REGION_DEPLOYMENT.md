# Multi-Region Deployment Guide

This guide covers deploying the Bing Grounding MCP service across multiple Azure regions with APIM as the global entry point.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Azure API Management                                    │
│                    (Global MCP Server Endpoint)                                  │
│                                                                                  │
│   https://apim-xxx.azure-api.net/bing-grounding-mcp/mcp                         │
│                                                                                  │
│   Features:                                                                      │
│   ├── Geo-routing (EU → West Europe, Others → East US)                          │
│   ├── Session affinity (sticky sessions per region)                             │
│   ├── Circuit breaker (automatic failover on errors)                            │
│   └── Health-based load balancing                                               │
└─────────────────────────────┬───────────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
            ▼                                   ▼
┌───────────────────────────┐     ┌───────────────────────────┐
│      East US (Primary)    │     │    West Europe (Secondary)│
│                           │     │                           │
│  ┌─────────────────────┐  │     │  ┌─────────────────────┐  │
│  │    App Service      │  │     │  │    App Service      │  │
│  └──────────┬──────────┘  │     │  └──────────┬──────────┘  │
│             │             │     │             │             │
│  ┌──────────▼──────────┐  │     │  ┌──────────▼──────────┐  │
│  │  AI Foundry Project │  │     │  │  AI Foundry Project │  │
│  │  • 1x gpt-4o agent  │  │     │  │  • 1x gpt-4o agent  │  │
│  │  • 1x gpt-4.1-mini  │  │     │  │  • 1x gpt-4.1-mini  │  │
│  │  • Bing Grounding   │  │     │  │  • Bing Grounding   │  │
│  └─────────────────────┘  │     │  └─────────────────────┘  │
└───────────────────────────┘     └───────────────────────────┘
```

## Why Multi-Region?

| Benefit | Description |
|---------|-------------|
| **Separate Quotas** | Each region has its own TPM/RPM limits |
| **Lower Latency** | Users route to nearest region |
| **High Availability** | Region failure doesn't take down service |
| **Geographic Compliance** | Data can stay within region boundaries |

## Agent Pool Strategy

### ❌ Don't Do This (Single Region)
```
Region: East US
├── gpt-4o agent 1
├── gpt-4o agent 2    ← Same quota, no benefit
├── gpt-4.1-mini agent 1
└── gpt-4.1-mini agent 2  ← Same quota, no benefit
```

### ✅ Do This (Multi-Region)
```
Region: East US          Region: West Europe
├── gpt-4o agent 1       ├── gpt-4o agent 1
└── gpt-4.1-mini agent 1 └── gpt-4.1-mini agent 1
    ↓                        ↓
  Own quota                Own quota
```

## Deployment Options

### Option 1: Azure Developer CLI (Recommended)

```bash
# Set environment variables
azd env set AZURE_LOCATION eastus
azd env set AZURE_SECONDARY_LOCATION westeurope
azd env set agentPoolSizeGpt4o 1
azd env set agentPoolSizeGpt41Mini 1

# Deploy using multi-region template
azd up --template infra/main-multiregion.bicep
```

### Option 2: Direct Bicep Deployment

```bash
# Deploy to both regions
az deployment sub create \
  --location eastus \
  --template-file infra/main-multiregion.bicep \
  --parameters environmentName=prod \
               location=eastus \
               secondaryLocation=westeurope \
               agentPoolSizeGpt4o=1 \
               agentPoolSizeGpt41Mini=1
```

### Option 3: Separate Regional Deployments

Deploy each region independently, then configure APIM:

```bash
# Deploy East US
az deployment group create \
  --resource-group rg-bing-mcp-eastus \
  --template-file infra/resources-region.bicep \
  --parameters location=eastus regionIdentifier=primary

# Deploy West Europe  
az deployment group create \
  --resource-group rg-bing-mcp-westeurope \
  --template-file infra/resources-region.bicep \
  --parameters location=westeurope regionIdentifier=secondary

# Deploy APIM with both backends
az deployment group create \
  --resource-group rg-bing-mcp-eastus \
  --template-file infra/apim-multiregion.bicep \
  --parameters primaryWebAppHostname=app-eastus.azurewebsites.net \
               secondaryWebAppHostname=app-westeurope.azurewebsites.net
```

## APIM Policy Configuration

The APIM policy ([apim-policy.xml](../apim-policy.xml)) handles:

### Geo-Routing
```xml
<!-- European clients → West Europe -->
var europeanPrefixes = new[] { "EU", "europe", "uk", "de", "fr", ... };
if (clientRegion contains europeanPrefix) return "westeurope";

<!-- All others → East US -->
return "eastus";
```

### Session Affinity
```xml
<!-- Cookie keeps user on same region for conversation continuity -->
Set-Cookie: APIM-Backend-Region=eastus; Path=/; Max-Age=86400
```

### Circuit Breaker
```xml
<!-- On 500/429 errors, mark region unhealthy for 30 seconds -->
<cache-store-value key="backend-health-eastus" value="unhealthy" duration="30" />
```

## Configuration Files

| File | Purpose |
|------|---------|
| [infra/main-multiregion.bicep](../infra/main-multiregion.bicep) | Main template for multi-region deployment |
| [infra/resources-region.bicep](../infra/resources-region.bicep) | Per-region resources (AI Foundry + App Service) |
| [infra/apim-multiregion.bicep](../infra/apim-multiregion.bicep) | APIM with geo-routing policy |
| [apim-policy.xml](../apim-policy.xml) | APIM policy with geo-routing and failover |

## Post-Deployment Steps

### 1. Create Agents in Each Region

```bash
# East US
AZURE_AI_PROJECT_ENDPOINT=https://foundry-eastus.cognitiveservices.azure.com/api/projects/proj-eastus
python scripts/postprovision_create_agents.py

# West Europe
AZURE_AI_PROJECT_ENDPOINT=https://foundry-westeurope.cognitiveservices.azure.com/api/projects/proj-westeurope
python scripts/postprovision_create_agents.py
```

### 2. Verify APIM Named Values

Ensure these are set correctly in APIM:
- `EASTUS_WEBAPP_HOSTNAME` → `app-xxx-eastus.azurewebsites.net`
- `WESTEUROPE_WEBAPP_HOSTNAME` → `app-xxx-westeurope.azurewebsites.net`

### 3. Test Geo-Routing

```bash
# Test from different regions (use VPN or Azure Cloud Shell in different regions)

# Should route to East US
curl -H "X-Azure-ClientRegion: US" https://apim-xxx.azure-api.net/bing-grounding/health

# Should route to West Europe
curl -H "X-Azure-ClientRegion: EU" https://apim-xxx.azure-api.net/bing-grounding/health
```

## Monitoring

### Check Which Region Served Request

Response headers include:
- `X-Served-By-Region: eastus` or `westeurope`
- `X-Client-Preferred-Region: eastus` (based on geo-detection)

### Azure Monitor Queries

```kusto
// Requests by region
AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS" or Category == "GatewayLogs"
| summarize count() by backendRegion = tostring(parse_json(responseHeaders)["X-Served-By-Region"])
| render piechart

// Failover events
AzureDiagnostics
| where message contains "unhealthy"
| project TimeGenerated, backendRegion, message
```

## Cost Considerations

| Resource | Per Region | Total (2 Regions) |
|----------|------------|-------------------|
| App Service (B1) | ~$13/month | ~$26/month |
| AI Foundry | Pay-per-use | Pay-per-use |
| APIM (Consumption) | ~$3.50/million calls | ~$3.50/million calls |

**Note**: APIM is deployed once (primary region) and routes to both regions.

## Troubleshooting

### Region Not Receiving Traffic

1. Check APIM named values are correct
2. Verify App Service is running in both regions
3. Check circuit breaker cache (wait 30 seconds if recently unhealthy)

### High Latency

1. Verify geo-routing is working (check `X-Served-By-Region` header)
2. Ensure users aren't being routed to distant region due to session cookie

### Agent Not Found

1. Ensure agents were created in BOTH regions
2. Check `AZURE_AI_PROJECT_ENDPOINT` is set correctly per region
3. Verify agent naming convention: `agent_bing__gpt4o__1`
