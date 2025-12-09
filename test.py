"""
Test script for Semantic Kernel agent using Bing Grounding MCP server.

This demonstrates:
1. Semantic Kernel agent with Azure OpenAI
2. MCP client connecting to MCP server (SSE transport)
3. Using MCP tools from the server in agent workflows
"""

import asyncio
import os
import sys

from dotenv import load_dotenv
from mcp import ClientSession
from mcp.client.sse import sse_client
from semantic_kernel import Kernel
from semantic_kernel.connectors.ai.open_ai import AzureChatCompletion
from semantic_kernel.contents import ChatHistory
from semantic_kernel.functions import KernelArguments, kernel_function

# Load environment variables
load_dotenv()


class MCPToolsPlugin:
    """
    Plugin that wraps MCP server tools for use in Semantic Kernel.
    
    This plugin connects to an MCP server and exposes its tools
    as Semantic Kernel functions that can be called by agents.
    """

    def __init__(self, mcp_session: ClientSession):
        """
        Initialize the MCP tools plugin.
        
        Args:
            mcp_session: Active MCP client session
        """
        self.session = mcp_session
        self._tools = None

    async def initialize(self):
        """Initialize and list available tools from MCP server."""
        result = await self.session.list_tools()
        self._tools = {tool.name: tool for tool in result.tools}
        print(f"[MCP] Connected to server with {len(self._tools)} tools:")
        for tool in self._tools.values():
            print(f"  - {tool.name}: {tool.description}")

    @kernel_function(
        name="bing_grounding_search",
        description="Search the web using Bing with AI-powered grounding and get cited responses. Use this for real-time information, current events, facts, and web research.",
    )
    async def bing_grounding_search(self, query: str) -> str:
        """
        Call the bing_grounding tool from the MCP server.
        
        Args:
            query: The search query or question to research
            
        Returns:
            Formatted response with content and citations
        """
        try:
            print(f"\n[MCP Tool] Calling bing_grounding tool...")
            print(f"[MCP Tool] Query: {query}")
            
            # Call the MCP tool
            result = await self.session.call_tool("bing_grounding", arguments={"query": query})
            
            # Extract response content
            if result.content and len(result.content) > 0:
                response = result.content[0].text
                print(f"[MCP Tool] Success! Received response")
                return response
            else:
                error_msg = "No response from MCP tool"
                print(f"[MCP Tool] Error: {error_msg}")
                return f"Error: {error_msg}"
            
        except Exception as e:
            error_msg = f"MCP tool error: {str(e)}"
            print(f"[MCP Tool] Error: {error_msg}")
            return f"Error: {error_msg}"


async def main():
    """
    Main test function that creates a Semantic Kernel agent with MCP tools.
    """
    
    print("=" * 80)
    print("Semantic Kernel Agent with MCP Server Tools")
    print("=" * 80)
    
    # Get configuration from environment
    azure_openai_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    azure_openai_api_key = os.getenv("AZURE_OPENAI_API_KEY")
    azure_openai_deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o")
    
    apim_mcp_url = os.getenv("APIM_MCP_SERVER_URL")
    apim_subscription_key = os.getenv("APIM_SUBSCRIPTION_KEY")
    
    # Validate required configuration
    if not azure_openai_endpoint or not apim_mcp_url:
        print("\n[ERROR] Missing required environment variables")
        print("Please set in .env file:")
        print("  AZURE_OPENAI_ENDPOINT=https://your-openai.openai.azure.com/")
        print("  AZURE_OPENAI_API_KEY=your-api-key")
        print("  AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o")
        print("  APIM_MCP_SERVER_URL=https://your-apim.azure-api.net/your-api-mcp/mcp")
        print("  APIM_SUBSCRIPTION_KEY=your-subscription-key (if required)")
        sys.exit(1)
    
    print(f"\n[Config] Azure OpenAI Endpoint: {azure_openai_endpoint}")
    print(f"[Config] Deployment: {azure_openai_deployment}")
    print(f"[Config] APIM MCP Server: {apim_mcp_url}")
    
    # Initialize Semantic Kernel
    print("\n[1/5] Initializing Semantic Kernel...")
    kernel = Kernel()
    
    # Add Azure OpenAI chat completion service
    print("[2/5] Configuring Azure OpenAI service...")
    kernel.add_service(
        AzureChatCompletion(
            service_id="chat",
            endpoint=azure_openai_endpoint,
            api_key=azure_openai_api_key,
            deployment_name=azure_openai_deployment,
        )
    )
    
    # Connect to APIM-hosted MCP server
    print("[3/5] Connecting to APIM MCP server...")
    
    # Build headers for APIM authentication
    headers = {}
    if apim_subscription_key:
        headers["Ocp-Apim-Subscription-Key"] = apim_subscription_key
    
    # APIM natively exposes REST APIs as MCP servers via HTTP/SSE
    async with sse_client(apim_mcp_url, headers=headers) as (read, write):
        async with ClientSession(read, write) as session:
            # Initialize session
            await session.initialize()
            
            # Create and initialize MCP tools plugin
            print("[4/5] Loading MCP tools...")
            mcp_plugin = MCPToolsPlugin(session)
            await mcp_plugin.initialize()
            
            # Add plugin to kernel
            kernel.add_plugin(mcp_plugin, plugin_name="mcp_tools")
            
            # Create chat history
            chat_history = ChatHistory()
            chat_history.add_system_message(
                "You are a helpful research assistant with access to web search via Bing Grounding. "
                "When asked about current events, facts, or information that requires web research, "
                "use the bing_grounding_search tool to get accurate, cited information. "
                "Always include citations in your responses when using web search results."
            )
            
            # Test queries
            test_queries = [
                "What are the latest developments in Azure AI as of December 2025?",
                "What is the current price of Bitcoin and what factors are affecting it?",
                "Tell me about recent breakthroughs in quantum computing.",
            ]
            
            print("[5/5] Running test queries with automatic tool calling...\n")
            print("=" * 80)
            
            # Get chat completion service
            chat_service = kernel.get_service("chat")
            
            # Enable automatic function calling
            execution_settings = kernel.get_prompt_execution_settings_from_service_id("chat")
            execution_settings.function_choice_behavior = kernel.get_function_choice_behavior_from_service(
                chat_service
            )
            
            for i, query in enumerate(test_queries, 1):
                print(f"\n{'=' * 80}")
                print(f"Test Query {i}/{len(test_queries)}")
                print(f"{'=' * 80}")
                print(f"\nUser: {query}\n")
                
                # Add user message to history
                chat_history.add_user_message(query)
                
                # Get response with automatic tool calling
                print("[Agent] Processing query with Semantic Kernel...")
                response = await chat_service.get_chat_message_contents(
                    chat_history=chat_history,
                    settings=execution_settings,
                    kernel=kernel,
                )
                
                # Extract assistant message
                assistant_message = response[0].content
                
                # Add to history
                chat_history.add_assistant_message(assistant_message)
                
                # Display response
                print(f"\n[Agent] Response:\n")
                print(assistant_message)
                print(f"\n{'=' * 80}\n")
                
                # Small delay between queries
                if i < len(test_queries):
                    await asyncio.sleep(2)
            
            print("\n" + "=" * 80)
            print("Test completed successfully!")
            print("=" * 80)


def interactive_mode():
    """
    Interactive mode for testing queries manually.
    """
    print("\n" + "=" * 80)
    print("Interactive Mode - Semantic Kernel Agent with MCP Tools")
    print("=" * 80)
    print("\nType your queries below. Type 'exit' or 'quit' to stop.\n")
    
    async def interactive_loop():
        # Get configuration
        azure_openai_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        azure_openai_api_key = os.getenv("AZURE_OPENAI_API_KEY")
        azure_openai_deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o")
        apim_mcp_url = os.getenv("APIM_MCP_SERVER_URL")
        apim_subscription_key = os.getenv("APIM_SUBSCRIPTION_KEY")
        
        if not azure_openai_endpoint or not apim_mcp_url:
            print("[ERROR] Missing required environment variables")
            print("Required: AZURE_OPENAI_ENDPOINT, APIM_MCP_SERVER_URL")
            return
        
        # Initialize kernel
        kernel = Kernel()
        kernel.add_service(
            AzureChatCompletion(
                service_id="chat",
                endpoint=azure_openai_endpoint,
                api_key=azure_openai_api_key,
                deployment_name=azure_openai_deployment,
            )
        )
        
        # Connect to APIM-hosted MCP server via HTTP/SSE
        headers = {}
        if apim_subscription_key:
            headers["Ocp-Apim-Subscription-Key"] = apim_subscription_key
        
        async with sse_client(apim_mcp_url, headers=headers) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                
                # Add MCP tools plugin
                mcp_plugin = MCPToolsPlugin(session)
                await mcp_plugin.initialize()
                kernel.add_plugin(mcp_plugin, plugin_name="mcp_tools")
                
                # Create chat history
                chat_history = ChatHistory()
                chat_history.add_system_message(
                    "You are a helpful research assistant with access to web search via Bing Grounding. "
                    "Use the bing_grounding_search tool for current information and always cite sources."
                )
                
                # Get chat service with auto function calling
                chat_service = kernel.get_service("chat")
                execution_settings = kernel.get_prompt_execution_settings_from_service_id("chat")
                execution_settings.function_choice_behavior = kernel.get_function_choice_behavior_from_service(
                    chat_service
                )
                
                while True:
                    # Get user input
                    user_input = input("\nYou: ").strip()
                    
                    if user_input.lower() in ['exit', 'quit', 'q']:
                        print("\nExiting interactive mode...")
                        break
                    
                    if not user_input:
                        continue
                    
                    # Add to history
                    chat_history.add_user_message(user_input)
                    
                    # Get response
                    print("\n[Agent] Thinking...")
                    response = await chat_service.get_chat_message_contents(
                        chat_history=chat_history,
                        settings=execution_settings,
                        kernel=kernel,
                    )
                    
                    assistant_message = response[0].content
                    chat_history.add_assistant_message(assistant_message)
                    
                    # Display response
                    print(f"\nAgent: {assistant_message}\n")
                    print("-" * 80)
    
    asyncio.run(interactive_loop())


if __name__ == "__main__":
    # Check command line arguments
    if len(sys.argv) > 1 and sys.argv[1] == "--interactive":
        interactive_mode()
    else:
        # Run automated tests
        asyncio.run(main())
        
        print("\n" + "=" * 80)
        print("Tip: Run with --interactive flag for manual testing:")
        print("  python test.py --interactive")
        print("=" * 80)
