"""Agent Pool Manager - Discovers all agents from environment variables"""
import os
import re
from typing import Dict, List

def discover_agents() -> Dict[str, List[str]]:
    """
    Discover all agent IDs from environment variables.
    
    Returns:
        Dict with model names as keys and lists of agent IDs as values
        Example: {
            "gpt-4o": ["asst_xxx1", "asst_xxx2"],
            "gpt-4-turbo": ["asst_xxx3", "asst_xxx4"]
        }
    """
    agents = {}
    
    # Pattern: AZURE_AI_AGENT_{MODEL}_{INDEX}
    # Example: AZURE_AI_AGENT_GPT4O_1, AZURE_AI_AGENT_GPT4_TURBO_2
    pattern = re.compile(r'^AZURE_AI_AGENT_([A-Z0-9_]+)_(\d+)$')
    
    model_mapping = {
        # GPT-5 series
        "GPT5": "gpt-5",
        "GPT5_MINI": "gpt-5-mini",
        "GPT5_NANO": "gpt-5-nano",
        "GPT5_PRO": "gpt-5-pro",
        "GPT5_CHAT": "gpt-5-chat",
        
        # GPT-4.1 series
        "GPT41": "gpt-4.1",
        "GPT41_MINI": "gpt-4.1-mini",
        "GPT41_NANO": "gpt-4.1-nano",
        
        # GPT-4o series
        "GPT4O": "gpt-4o",
        
        # GPT-4 series
        "GPT4": "gpt-4",
        "GPT4_32K": "gpt-4-32k",
        "GPT4_TURBO": "gpt-4-turbo",
        
        # GPT-3.5 series
        "GPT35_TURBO": "gpt-35-turbo",
        "GPT35_TURBO_16K": "gpt-35-turbo-16k",
        
        # o-series
        "O3": "o3",
        "O3_MINI": "o3-mini",
        "O1": "o1",
        "O1_MINI": "o1-mini",
        "O4_MINI": "o4-mini"
    }
    
    for key, value in os.environ.items():
        match = pattern.match(key)
        if match and value:
            model_key = match.group(1)
            index = match.group(2)
            
            # Map to actual model name
            model_name = model_mapping.get(model_key, model_key.lower().replace('_', '-'))
            
            if model_name not in agents:
                agents[model_name] = []
            
            agents[model_name].append({
                "id": value,
                "index": int(index),
                "env_key": key
            })
    
    # Sort by index within each model
    for model in agents:
        agents[model].sort(key=lambda x: x["index"])
    
    return agents


def get_all_agent_ids() -> List[Dict[str, str]]:
    """
    Get flat list of all agents with their metadata.
    
    Returns:
        List of dicts with agent_id, model, and index
        Example: [
            {"agent_id": "asst_xxx", "model": "gpt-4o", "index": 1, "route": "gpt4o_1"},
            {"agent_id": "asst_yyy", "model": "gpt-4o", "index": 2, "route": "gpt4o_2"}
        ]
    """
    agents_by_model = discover_agents()
    all_agents = []
    
    for model, agents_list in agents_by_model.items():
        for agent_info in agents_list:
            # Create route-friendly name: gpt4o_1, gpt4_turbo_2, gpt35_turbo_1
            route = model.replace('-', '').replace('.', '') + '_' + str(agent_info['index'])
            
            all_agents.append({
                "agent_id": agent_info["id"],
                "model": model,
                "index": agent_info["index"],
                "route": route
            })
    
    return all_agents
