#!/usr/bin/env python3
"""
Create multiple Bing grounding agents in Azure AI Project.

This script creates agents with Bing Search grounding enabled.
It uses the Azure AI Projects SDK to programmatically create agents.

Usage:
    python scripts/create-agents.py
"""
import os
import sys
from pathlib import Path

# Ensure required packages are installed
try:
    from azure.ai.projects import AIProjectClient
    from azure.ai.agents.models import BingGroundingTool
    from azure.identity import DefaultAzureCredential
except ImportError:
    print("?? Installing required packages...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "azure-ai-projects", "azure-identity", "azure-ai-agents"])
    from azure.ai.projects import AIProjectClient
    from azure.ai.agents.models import BingGroundingTool
    from azure.identity import DefaultAzureCredential

# Number of agents to create
NUM_AGENTS = 10

def get_env_value(key: str) -> str:
    """Get environment variable value from current azd environment .env file."""
    # First, determine which environment we're in by checking azd's config
    env_name = None
    
    # Try to read the default environment from .azure/config.json
    import json
    config_file = Path(".azure/config.json")
    if config_file.exists():
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                config = json.load(f)
                env_name = config.get("defaultEnvironment")
        except Exception:
            pass
    
    # Fallback: check for azd's environment indicator files
    if not env_name:
        azure_dir = Path(".azure")
        if azure_dir.exists():
            # Look for .env files in subdirectories to find current environment
            for env_dir in azure_dir.iterdir():
                if env_dir.is_dir() and (env_dir / ".env").exists():
                    # Check if this env has the key we need (like AZURE_AI_PROJECT_ENDPOINT)
                    test_file = env_dir / ".env"
                    with open(test_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if 'AZURE_AI_PROJECT_ENDPOINT' in content:
                            env_name = env_dir.name
                            break
    
    if not env_name:
        env_name = "dev"  # Fallback default
    
    # Read from .azure/{env}/.env
    env_file = Path(f".azure/{env_name}/.env")
    if env_file.exists():
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    if '=' in line:
                        k, v = line.split('=', 1)
                        if k.strip() == key:
                            return v.strip().strip('"')
    return ""

def set_env_value(key: str, value: str):
    """Set environment variable in current azd environment's .env file."""
    # Detect current environment the same way as get_env_value
    env_name = None
    
    # Try to read the default environment from .azure/config.json
    import json
    config_file = Path(".azure/config.json")
    if config_file.exists():
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                config = json.load(f)
                env_name = config.get("defaultEnvironment")
        except Exception:
            pass
    
    # Fallback: check for azd's environment indicator files
    if not env_name:
        azure_dir = Path(".azure")
        if azure_dir.exists():
            for env_dir in azure_dir.iterdir():
                if env_dir.is_dir() and (env_dir / ".env").exists():
                    test_file = env_dir / ".env"
                    with open(test_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if 'AZURE_AI_PROJECT_ENDPOINT' in content:
                            env_name = env_dir.name
                            break
    
    if not env_name:
        env_name = "dev"
    
    env_file = Path(f".azure/{env_name}/.env")
    env_file.parent.mkdir(parents=True, exist_ok=True)
    
    lines = []
    found = False
    
    if env_file.exists():
        with open(env_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    
    # Update or add the key
    for i, line in enumerate(lines):
        if line.strip() and not line.startswith('#'):
            if '=' in line:
                k, _ = line.split('=', 1)
                if k.strip() == key:
                    lines[i] = f'{key}="{value}"\n'
                    found = True
                    break
    
    if not found:
        lines.append(f'{key}="{value}"\n')
    
    with open(env_file, 'w', encoding='utf-8') as f:
        f.writelines(lines)

def main():
    """Create Bing grounding agents."""
    print("?? Creating Bing Grounding Agent Pools...")
    print()
    
    # Get AI Project endpoint and resource ID from .azure/{env}/.env file
    project_endpoint = get_env_value("AZURE_AI_PROJECT_ENDPOINT")
    project_resource_id = get_env_value("AZURE_AI_PROJECT_RESOURCE_ID")
    
    if not project_endpoint:
        print("? Error: AZURE_AI_PROJECT_ENDPOINT not found in .azure/ folder")
        print("   Run 'azd provision' first to create the AI Project.")
        sys.exit(1)
    
    if not project_resource_id:
        print("? Error: AZURE_AI_PROJECT_RESOURCE_ID not found in .azure/ folder")
        print("   Run 'azd provision' first to create the AI Project.")
        sys.exit(1)
    
    # Bing connection ID - optional for now (connection can be created later)
    # For beta10 SDK with hub-based projects, Bing tool may work without explicit connection ID
    bing_connection_id = get_env_value("AZURE_BING_CONNECTION_ID")
    
    # Model configurations with pool sizes
    # Note: gpt-4o-mini and gpt-5 models do NOT support Bing grounding
    # GPT-4 Turbo removed due to deprecation - using GPT-4o, GPT-4, and GPT-3.5 Turbo
    model_configs = [
        {"name": "gpt-4o", "key": "GPT4O", "pool_size_env": "AGENT_POOL_SIZE_GPT4O", "default_size": 12},
        {"name": "gpt-4", "key": "GPT4", "pool_size_env": "AGENT_POOL_SIZE_GPT4", "default_size": 0},
        {"name": "gpt-35-turbo", "key": "GPT35_TURBO", "pool_size_env": "AGENT_POOL_SIZE_GPT35_TURBO", "default_size": 0},
    ]
    
    # Read pool sizes from environment
    for config in model_configs:
        pool_size_str = get_env_value(config["pool_size_env"])
        try:
            config["pool_size"] = int(pool_size_str) if pool_size_str else config["default_size"]
        except ValueError:
            config["pool_size"] = config["default_size"]
    
    total_agents = sum(c["pool_size"] for c in model_configs)
    
    print(f"?? AI Project Endpoint: {project_endpoint}")
    print(f"?? Agent Pool Configuration:")
    for config in model_configs:
        print(f"   {config['name']}: {config['pool_size']} agents")
    print(f"   Total: {total_agents} agents")
    print()
    
    try:
        # Initialize AI Project client using HTTPS endpoint (for Foundry projects with GA SDK v1.0.0)
        # For GA SDK, we need to construct the full project endpoint
        credential = DefaultAzureCredential()
        
        # For GA SDK v1.0.0, use the project-specific AI Foundry API endpoint
        # Get required parameters for AIProjectClient v1.0.0+
        foundry_name = get_env_value("AZURE_FOUNDRY_NAME")
        project_name = get_env_value("AZURE_AI_PROJECT_NAME")
        
        # Format: https://{foundry}.services.ai.azure.com/api/projects/{project}
        project_endpoint = f"https://{foundry_name}.services.ai.azure.com/api/projects/{project_name}"
        
        print(f"?? Using project endpoint: {project_endpoint}")
        print()
        
        project_client = AIProjectClient(
            endpoint=project_endpoint,
            credential=credential
        )
        
        agent_ids = []
        agent_counter = 1
        
        # Create agents for each model pool
        for config in model_configs:
            model_name = config["name"]
            model_key = config["key"]
            pool_size = config["pool_size"]
            
            if pool_size == 0:
                continue
            
            print(f"\n?? Creating {model_name} pool ({pool_size} agents)...")
            
            for i in range(1, pool_size + 1):
                # Naming convention: agent_bing_{model_key}_{index}
                # Examples: agent_bing_gpt4o_1, agent_bing_gpt4_turbo_2, agent_bing_gpt35_turbo_1
                agent_name = f"agent_bing_{model_key.lower()}_{i}"
                print(f"  [{agent_counter}] Creating {agent_name}...", end=" ")
                
                try:
                    # Get or construct Bing connection ID
                    # The connection will be auto-provisioned when the agent is first used
                    try:
                        bing_connection_id = get_env_value("AZURE_BING_CONNECTION_ID")
                    except:
                        # Construct default connection ID if not in environment
                        subscription_id = get_env_value("AZURE_SUBSCRIPTION_ID")
                        resource_group = get_env_value("AZURE_RESOURCE_GROUP")
                        bing_connection_id = f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}/providers/Microsoft.CognitiveServices/accounts/{foundry_name}/projects/{project_name}/connections/default-bing"
                    
                    # Initialize Bing Grounding tool
                    bing = BingGroundingTool(connection_id=bing_connection_id)
                    
                    # Create agent with Bing grounding
                    agent = project_client.agents.create_agent(
                        model=model_name,
                        name=agent_name,
                        instructions="You are a helpful assistant with access to Bing Search. Use Bing Search to provide accurate, up-to-date information with citations.",
                        tools=bing.definitions
                    )
                    
                    agent_ids.append({"id": agent.id, "name": agent_name, "model": model_name})
                    print(f"? {agent.id}")
                    
                    # Store in environment with consistent naming
                    # AZURE_AI_AGENT_GPT4O_1, AZURE_AI_AGENT_GPT4_TURBO_2, etc.
                    env_key = f"AZURE_AI_AGENT_{model_key}_{i}"
                    set_env_value(env_key, agent.id)
                    
                    agent_counter += 1
                    
                except Exception as e:
                    print(f"? Failed: {str(e)}")
                    # Print more details for debugging
                    if hasattr(e, 'response'):
                        print(f"   Response: {e.response}")
                    if hasattr(e, 'status_code'):
                        print(f"   Status: {e.status_code}")
                    continue
        
        print()
        print(f"\n? Successfully created {len(agent_ids)}/{total_agents} agents")
        print()
        
        if agent_ids:
            # Set the first agent as the default
            set_env_value("AZURE_AI_AGENT_ID", agent_ids[0]["id"])
            print(f"?? Default agent: {agent_ids[0]['name']} ({agent_ids[0]['id']})")
            print()
            
            # Detect which env we're in for display (use same logic as get_env_value)
            import json
            env_name = "unknown"
            config_file = Path(".azure/config.json")
            if config_file.exists():
                try:
                    with open(config_file, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                        env_name = config.get("defaultEnvironment", "unknown")
                except Exception:
                    # Fallback to directory scanning
                    azure_dir = Path(".azure")
                    for env_dir in azure_dir.iterdir():
                        if env_dir.is_dir() and (env_dir / ".env").exists():
                            with open(env_dir / ".env", 'r') as f:
                                if 'AZURE_AI_PROJECT_ENDPOINT' in f.read():
                                    env_name = env_dir.name
                                    break
            
            print(f"Agent IDs saved to .azure/{env_name}/.env:")
            
            # Group by model for cleaner output
            for config in model_configs:
                model_agents = [a for a in agent_ids if a["model"] == config["name"]]
                if model_agents:
                    print(f"\n  {config['name']}:")
                    for agent in model_agents:
                        env_key = f"AZURE_AI_AGENT_{config['key']}_{agent['name'].split('_')[-1]}"
                        print(f"    {env_key}={agent['id']}")
            
            print()
            print("? Agent pools are ready to use!")
        else:
            print("??  No agents were created successfully")
            sys.exit(1)
            
    except Exception as e:
        print(f"? Error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
