#!/usr/bin/env python3
"""
Update Container App with agent environment variables.

This script runs after azd deploys to the Container App.
It updates the container app environment variables with all agent IDs
created during postprovision.
"""
import os
import sys
import json
import subprocess
from pathlib import Path

def run_command(cmd: list[str]) -> tuple[bool, str, str]:
    """Run a command and return (success, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='replace'
        )
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def get_env_value(key: str) -> str:
    """Get environment variable from .azure/{env}/.env"""
    config_file = Path(".azure/config.json")
    env_name = "prod"
    
    if config_file.exists():
        with open(config_file, 'r', encoding='utf-8') as f:
            config = json.load(f)
            env_name = config.get("defaultEnvironment", "prod")
    
    env_dir = Path(f".azure/{env_name}")
    env_file = env_dir / ".env"
    
    if env_file.exists():
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line.startswith(f"{key}="):
                    value = line.split("=", 1)[1]
                    return value.strip('"').strip("'")
    
    return os.environ.get(key, "")

def main():
    resource_group = get_env_value("AZURE_RESOURCE_GROUP")
    container_app_name = get_env_value("AZURE_CONTAINER_APP_NAME")
    image_name = get_env_value("SERVICE_API_IMAGE_NAME")

    print("=" * 80)
    print("Update Container App Environment Variables")
    print("=" * 80)
    print()
    print(f"Resource Group: {resource_group}")
    print(f"Container App: {container_app_name}")
    print(f"Image: {image_name}")
    print()

    # Collect all agent environment variables
    agent_env_vars = []
    
    # Get AI Project info
    project_endpoint = get_env_value("AZURE_AI_PROJECT_ENDPOINT")
    project_name = get_env_value("AZURE_AI_PROJECT_NAME")
    
    if project_endpoint:
        agent_env_vars.append({
            "name": "AZURE_AI_PROJECT_ENDPOINT",
            "value": project_endpoint
        })
    
    if project_name:
        agent_env_vars.append({
            "name": "AZURE_AI_PROJECT_NAME",
            "value": project_name
        })
    
    # Collect all agent IDs from environment
    # Pattern: AZURE_AI_AGENT_GPT4O_1, AZURE_AI_AGENT_GPT4_2, etc.
    env_file_path = Path(f".azure/{get_env_value('AZURE_ENV_NAME') or 'prod'}/.env")
    if not env_file_path.exists():
        # Try to find the env file
        azure_dir = Path(".azure")
        for env_dir in azure_dir.iterdir():
            if env_dir.is_dir() and (env_dir / ".env").exists():
                env_file_path = env_dir / ".env"
                break
    
    if env_file_path.exists():
        with open(env_file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line.startswith("AZURE_AI_AGENT_"):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"').strip("'")
                        agent_env_vars.append({
                            "name": key,
                            "value": value
                        })
    
    print(f"📋 Found {len(agent_env_vars)} environment variables to set")
    for env_var in agent_env_vars:
        if env_var["name"].startswith("AZURE_AI_AGENT_"):
            print(f"   {env_var['name']}: {env_var['value'][:20]}...")
    print()
    
    # Update container app with environment variables
    print("🚀 Updating Container App environment variables...")
    
    # Build the environment variables as comma-separated key=value pairs
    env_pairs = [f"{var['name']}={var['value']}" for var in agent_env_vars]
    
    cmd = [
        "az", "containerapp", "update",
        "--name", container_app_name,
        "--resource-group", resource_group,
        "--set-env-vars"
    ] + env_pairs
    
    success, stdout, stderr = run_command(cmd)
    
    if not success:
        print(f"❌ ERROR: Failed to update container app")
        print(f"   Command: {' '.join(cmd)}")
        print(f"   Error: {stderr}")
        return 1
    
    print("✅ Container App environment variables updated")
    print()
    print("=" * 80)
    print("Container App Update Complete")
    print("=" * 80)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
