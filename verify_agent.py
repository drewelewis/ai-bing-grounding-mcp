from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
import os

foundry_name = os.getenv('AZURE_AI_FOUNDRY_NAME')
project_name = os.getenv('AZURE_AI_PROJECT_NAME')
agent_id = os.getenv('AZURE_AI_AGENT_GPT4O_1')

endpoint = f"https://{foundry_name}.services.ai.azure.com/api/projects/{project_name}"
client = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())

agent = client.agents.get_agent(agent_id)
print(f"[OK] Agent verified: {agent.name}")
print(f"[OK] Agent ID: {agent.id}")
print(f"[OK] Model: {agent.model}")
print(f"[OK] Has tools: {len(agent.tools) > 0}")
