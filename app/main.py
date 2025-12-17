import json
import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from agents.agent_pool import get_all_agent_ids
from agents.bing_grounding import BingGroundingAgent

app = FastAPI(
    title="Bing Grounding API",
    description="API wrapper for Azure AI Agent with Bing grounding capabilities - Multiple agent instances",
    version="2.0.0"
)

# Request model
class QueryRequest(BaseModel):
    query: str

# Discover all agents on startup
AGENTS = {}
PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
AZURE_REGION = os.getenv("AZURE_REGION", "unknown")

@app.on_event("startup")
def startup_event():
    """Discover all agents from environment variables on startup"""
    if not PROJECT_ENDPOINT:
        print("⚠️  Warning: AZURE_AI_PROJECT_ENDPOINT not set")
        return
    
    all_agents = get_all_agent_ids()
    
    if not all_agents:
        print("⚠️  Warning: No agents found in environment variables")
        return
    
    # Create agent instance for each discovered agent
    for agent_info in all_agents:
        route = agent_info["route"]
        agent_id = agent_info["agent_id"]
        
        try:
            agent_instance = BingGroundingAgent(endpoint=PROJECT_ENDPOINT, agent_id=agent_id)
            
            AGENTS[route] = {
                "agent_id": agent_id,
                "model": agent_info["model"],
                "index": agent_info["index"],
                "instance": agent_instance
            }
            
            print(f"✅ Registered agent: {route} -> {agent_id} ({agent_info['model']})")
        except Exception as e:
            print(f"⚠️  Failed to initialize agent {route}: {e}")
    
    print(f"\n🚀 Total agents available: {len(AGENTS)}")


@app.get("/health")
async def health_check():
    """
    Health check endpoint.
    Returns 200 OK if the service is running.
    """
    return {
        "status": "ok",
        "service": "bing-grounding-api",
        "region": AZURE_REGION,
        "agents_loaded": len(AGENTS),
        "agents": list(AGENTS.keys())
    }


@app.get("/agents")
async def list_agents():
    """
    List all available agent endpoints.
    
    Returns:
        List of available agents with their routes and models
    """
    agents_list = []
    for route, info in AGENTS.items():
        agents_list.append({
            "route": f"/bing-grounding/{route}",
            "model": info["model"],
            "index": info["index"],
            "agent_id": info["agent_id"]
        })
    
    return {
        "total": len(agents_list),
        "agents": agents_list
    }


@app.post("/bing-grounding")
async def bing_grounding_with_model(query: str, model: str = "gpt-4o"):
    """
    Endpoint for Bing grounding with model selection.
    
    Args:
        query: Search query string
        model: Model to use (gpt-5, gpt-5-mini, gpt-4o, gpt-4, gpt-35-turbo). Defaults to gpt-4o
        
    Returns:
        JSON response with content and citations
        
    Example:
        POST /bing-grounding?query=What+is+Azure&model=gpt-4o
    """
    import random
    
    # Find all agents for the requested model
    model_agents = [route for route, info in AGENTS.items() if info["model"] == model]
    
    if not model_agents:
        # Fallback to gpt-4o if requested model not available
        model_agents = [route for route, info in AGENTS.items() if info["model"] == "gpt-4o"]
        if not model_agents:
            raise HTTPException(
                status_code=404,
                detail=f"No agents available for model '{model}' or fallback model 'gpt-4o'"
            )
    
    # Randomly select one agent from the model pool
    agent_route = random.choice(model_agents)
    
    try:
        agent_instance = AGENTS[agent_route]["instance"]
        response = agent_instance.chat(query)
        result = json.loads(response)
        result["metadata"] = {
            "agent_route": agent_route,
            "model": model,
            "agent_id": AGENTS[agent_route]["agent_id"],
            "region": AZURE_REGION
        }
        return result
    except Exception as e:
        return {
            "error": "processing_error",
            "message": str(e),
            "metadata": {
                "agent_route": agent_route,
                "model": model,
                "agent_id": AGENTS.get(agent_route, {}).get("agent_id", "unknown"),
                "region": AZURE_REGION
            }
        }


@app.post("/bing-grounding/{agent_route}")
async def bing_grounding_specific_agent(agent_route: str, request: QueryRequest):
    """
    Endpoint for specific Bing grounding agent by route.
    
    Args:
        agent_route: Agent route (e.g., "gpt4o_1", "gpt5_2")
        request: Query request body
        
    Returns:
        JSON response with content and citations
        
    Example routes:
        POST /bing-grounding/gpt4o_1
        POST /bing-grounding/gpt4o_2
        POST /bing-grounding/gpt5_1
        POST /bing-grounding/gpt5_2
    """
    if agent_route not in AGENTS:
        raise HTTPException(
            status_code=404,
            detail=f"Agent '{agent_route}' not found. Available: {list(AGENTS.keys())}"
        )
    
    try:
        agent_instance = AGENTS[agent_route]["instance"]
        response = agent_instance.chat(request.query)
        result = json.loads(response)
        result["metadata"] = {
            "agent_route": agent_route,
            "model": AGENTS[agent_route]["model"],
            "agent_id": AGENTS[agent_route]["agent_id"],
            "region": AZURE_REGION
        }
        return result
    except Exception as e:
        return {
            "error": "processing_error",
            "message": str(e),
            "metadata": {
                "agent_route": agent_route,
                "model": AGENTS[agent_route]["model"],
                "agent_id": AGENTS[agent_route]["agent_id"],
                "region": AZURE_REGION
            }
        }