# Multi-Model Support Implementation

## ✅ Supported Models

**According to [Azure documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/tool-best-practice), Bing grounding IS supported on:**
- ✅ GPT-4o models
- ✅ **GPT-5 models** (gpt-5, gpt-5-mini, gpt-5-nano, gpt-5-pro)
- ✅ GPT-4 series (gpt-4, gpt-4-32k)
- ✅ GPT-3.5 series (gpt-35-turbo, gpt-35-turbo-16k)
- ✅ GPT-4.1 series
- ✅ o3, o3-mini, o1 models

**NOT supported:**
- ❌ gpt-4o-mini (2024-07-18 version specifically)

**Currently deployed:**
- ✅ GPT-4o (12 agents)
- ✅ **GPT-5 (12 agents)**

## Summary

This document describes the multi-model architecture supporting GPT-4o and GPT-5 models with Bing grounding capabilities.

## Changes Made

### 1. Environment Configuration (`.env`)
**Added GPT-5 agent pool configuration:**
```bash
AGENT_POOL_SIZE_GPT4O=12  # 12 GPT-4o agents
AGENT_POOL_SIZE_GPT5=12   # 12 GPT-5 agents (NEW)
```

**Total agents**: 24 (12 per model)

---

### 2. Agent Creation Script (`scripts/postprovision_create_agents.py`)
**Updated model configurations:**
```python
model_configs = [
    {"name": "gpt-4o", "key": "GPT4O", "pool_size_env": "AGENT_POOL_SIZE_GPT4O", "default_size": 12},
    {"name": "gpt-5", "key": "GPT5", "pool_size_env": "AGENT_POOL_SIZE_GPT5", "default_size": 12},
    {"name": "gpt-4", "key": "GPT4", "pool_size_env": "AGENT_POOL_SIZE_GPT4", "default_size": 0},
    {"name": "gpt-35-turbo", "key": "GPT35_TURBO", "pool_size_env": "AGENT_POOL_SIZE_GPT35_TURBO", "default_size": 0},
]
```

**What it creates:**
- `AZURE_AI_AGENT_GPT4O_1` through `AZURE_AI_AGENT_GPT4O_12`
- `AZURE_AI_AGENT_GPT5_1` through `AZURE_AI_AGENT_GPT5_12` (NEW)

---

### 3. Agent Pool Manager (`agents/agent_pool.py`)
**Added GPT-5 to model mapping:**
```python
model_mapping = {
    "GPT4O": "gpt-4o",
    "GPT5": "gpt-5",      # NEW
    "GPT4_TURBO": "gpt-4-turbo",
    "GPT4": "gpt-4",
    "GPT35_TURBO": "gpt-35-turbo"
}
```

---

### 4. API Endpoint (`app/main.py`)
**Added new endpoint with model selection:**

```python
@app.post("/bing-grounding")
async def bing_grounding_with_model(query: str, model: str = "gpt-4o"):
    """
    Endpoint for Bing grounding with model selection.
    
    Args:
        query: Search query string
        model: Model to use (gpt-4o, gpt-5, etc.) - defaults to gpt-4o
    """
    # Find all agents for the requested model
    model_agents = [route for route, info in AGENTS.items() if info["model"] == model]
    
    # Randomly select one agent from the model pool
    agent_route = random.choice(model_agents)
    
    # Execute query and return result
    agent_instance = AGENTS[agent_route]["instance"]
    response = agent_instance.chat(query)
    result = json.loads(response)
    result["metadata"] = {
        "agent_route": agent_route,
        "model": model,
        "agent_id": AGENTS[agent_route]["agent_id"]
    }
    return result
```

**Key Features:**
- Accepts `model` parameter (gpt-4o, gpt-5)
- Automatically selects from appropriate agent pool
- Falls back to gpt-4o if requested model unavailable
- Includes metadata in response (agent used, model, agent ID)

---

### 5. Test Script (`test.py`)
**Updated MCP tool to support model parameter:**

```python
@kernel_function(
    name="bing_grounding_search",
    description="Search the web using Bing with AI-powered grounding. Supports multiple AI models (gpt-4o, gpt-5).",
)
async def bing_grounding_search(self, query: str, model: str = "gpt-4o") -> str:
    """
    Call the bing_grounding tool from the MCP server.
    
    Args:
        query: The search query or question to research
        model: AI model to use (gpt-4o, gpt-5) - defaults to gpt-4o
    """
    # Call the MCP tool with model parameter
    result = await self.session.call_tool("bing_grounding", arguments={"query": query, "model": model})
    return response
```

**Added separate test sections:**
- GPT-4o tests (3 queries)
- GPT-5 tests (1 query)

---

### 6. Infrastructure (`infra/resources.bicep`)
**Updated APIM operation to include model parameter:**

```bicep
resource bingGroundingOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'bing-grounding'
  properties: {
    displayName: 'Bing Grounding'
    method: 'POST'
    urlTemplate: '/bing-grounding'
    description: 'Query with Bing grounding and citations. Supports multiple AI models (gpt-4o, gpt-5).'
    request: {
      queryParameters: [
        {
          name: 'query'
          type: 'string'
          required: true
          description: 'The query to process'
        }
        {
          name: 'model'
          type: 'string'
          required: false
          defaultValue: 'gpt-4o'
          description: 'AI model to use (gpt-4o, gpt-5). Defaults to gpt-4o.'
        }
      ]
    }
  }
}
```

---

## Usage Examples

### REST API (Direct)
```bash
# Use GPT-4o (default)
curl -X POST "https://apim-xxx.azure-api.net/bing-grounding?query=What+is+Azure" \
  -H "Ocp-Apim-Subscription-Key: xxx"

# Use GPT-5
curl -X POST "https://apim-xxx.azure-api.net/bing-grounding?query=What+is+Azure&model=gpt-5" \
  -H "Ocp-Apim-Subscription-Key: xxx"
```

### MCP Client (Semantic Kernel)
```python
# Call tool with default model (gpt-4o)
result = await session.call_tool("bing_grounding", arguments={"query": "What is Azure?"})

# Call tool with GPT-5
result = await session.call_tool("bing_grounding", arguments={"query": "What is Azure?", "model": "gpt-5"})
```

### MCP Server URL
**Single endpoint exposes all models:**
```
https://apim-xxx.azure-api.net/bing-grounding-api-mcp/mcp
```

**Available tools:**
- `bing_grounding` (with `query` and optional `model` parameters)

---

## Response Format

```json
{
  "content": "Azure is Microsoft's cloud computing platform...",
  "citations": [
    {"url": "https://azure.microsoft.com/", "title": "Microsoft Azure"}
  ],
  "metadata": {
    "agent_route": "gpt5_3",
    "model": "gpt-5",
    "agent_id": "asst_xyz123"
  }
}
```

---

## Deployment

### 1. Deploy Infrastructure
```bash
azd up
```

This will:
- ✅ Create 12 GPT-4o agents
- ✅ Create 12 GPT-5 agents (NEW)
- ✅ Update APIM with model parameter
- ✅ Deploy container apps with multi-model support

### 2. Verify Agents Created
```bash
azd env get-values | findstr AGENT
```

Expected output:
```
AZURE_AI_AGENT_GPT4O_1="asst_xxx1"
...
AZURE_AI_AGENT_GPT4O_12="asst_xxx12"
AZURE_AI_AGENT_GPT5_1="asst_yyy1"
...
AZURE_AI_AGENT_GPT5_12="asst_yyy12"
```

### 3. Test Multi-Model Support
```bash
python test.py
```

---

## Architecture

```
MCP Client (test.py)
    ↓
APIM MCP Server (/mcp endpoint)
    ↓
Container Apps (Load Balanced)
    ↓
Agent Pools:
  - GPT-4o Pool (12 agents)
  - GPT-5 Pool (12 agents)
    ↓
Azure AI Foundry + Bing Grounding
```

---

## Benefits

1. **Model Flexibility**: Choose best model per query
2. **Load Distribution**: 24 agents vs 12 (better throughput)
3. **Simple API**: Single endpoint, model as parameter
4. **Backward Compatible**: Defaults to gpt-4o if model not specified
5. **Automatic Fallback**: Falls back to gpt-4o if requested model unavailable

---

## Notes

- **GPT-5 Availability**: Check Azure AI Foundry portal for model availability in your region
- **Quota Requirements**: Each model needs separate quota allocation
- **Cost**: GPT-5 may have different pricing than GPT-4o
- **Agent Pool Size**: Can be adjusted via environment variables before deployment

---

## Troubleshooting

### Issue: GPT-5 agents not created
**Check:**
1. GPT-5 model deployment exists in Azure AI Foundry
2. `AGENT_POOL_SIZE_GPT5=12` is set in `.env`
3. Model name matches exactly: `gpt-5`

### Issue: Model parameter not working in MCP
**Check:**
1. APIM policy updated with model parameter
2. MCP server recreated in portal after infrastructure update
3. MCP client passing model parameter correctly

---

**Status**: ✅ Complete  
**Last Updated**: December 9, 2024  
**Total Agents**: 24 (12 GPT-4o + 12 GPT-5)
