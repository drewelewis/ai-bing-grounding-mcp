// ============================================================================
// APIM Module for Multi-Region Setup
// Routes traffic to primary (East US) and secondary (West Europe) backends
// ============================================================================

param location string
param tags object
param apimServiceName string
param primaryWebAppHostname string
param secondaryWebAppHostname string
param primaryRegion string
param secondaryRegion string

// APIM instance
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'Bing MCP Multi-Region'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
    }
  }
}

// Named values for backend URLs (replaceable without policy changes)
resource namedValuePrimaryHost 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'EASTUS-WEBAPP-HOSTNAME'
  properties: {
    displayName: 'EASTUS_WEBAPP_HOSTNAME'
    value: primaryWebAppHostname
    secret: false
  }
}

resource namedValueSecondaryHost 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'WESTEUROPE-WEBAPP-HOSTNAME'
  properties: {
    displayName: 'WESTEUROPE_WEBAPP_HOSTNAME'
    value: secondaryWebAppHostname
    secret: false
  }
}

// Backend - Primary (East US)
resource backendPrimary 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apim
  name: 'backend-eastus'
  properties: {
    url: 'https://${primaryWebAppHostname}'
    protocol: 'http'
    description: 'Primary backend - East US App Service'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// Backend - Secondary (West Europe)
resource backendSecondary 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apim
  name: 'backend-westeurope'
  properties: {
    url: 'https://${secondaryWebAppHostname}'
    protocol: 'http'
    description: 'Secondary backend - West Europe App Service'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// API definition for Bing Grounding MCP
resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'bing-grounding-api'
  properties: {
    displayName: 'Bing Grounding MCP API'
    description: 'Multi-region Bing Grounding API with geo-routing'
    path: 'bing-grounding'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    serviceUrl: 'https://${primaryWebAppHostname}'
  }
}

// Health check operation
resource operationHealth 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
    description: 'Health check endpoint'
  }
}

// Chat operation for specific agent
resource operationChat 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'chat-agent'
  properties: {
    displayName: 'Chat with Agent'
    method: 'POST'
    urlTemplate: '/bing-grounding/{agentRoute}'
    description: 'Send chat query to specific agent'
    templateParameters: [
      {
        name: 'agentRoute'
        type: 'string'
        required: true
        description: 'Agent route identifier (e.g., gpt4o_1)'
      }
    ]
  }
}

// Chat operation for model selection
resource operationChatModel 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'chat-model'
  properties: {
    displayName: 'Chat with Model'
    method: 'POST'
    urlTemplate: '/chat/{model}'
    description: 'Send chat query using any agent of specified model type'
    templateParameters: [
      {
        name: 'model'
        type: 'string'
        required: true
        description: 'Model name (e.g., gpt-4o, gpt-4.1-mini)'
      }
    ]
  }
}

// MCP endpoint (for APIM native MCP server support)
resource operationMcp 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'mcp'
  properties: {
    displayName: 'MCP Endpoint'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Model Context Protocol endpoint'
  }
}

// List agents operation
resource operationListAgents 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'list-agents'
  properties: {
    displayName: 'List Agents'
    method: 'GET'
    urlTemplate: '/agents'
    description: 'List all available Bing grounding agents'
  }
}

// API-level policy with geo-routing
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<!--
    Multi-Region Load Balancing with Geo-Routing
    Routes EU clients to West Europe, others to East US
-->
<policies>
    <inbound>
        <base />
        
        <!-- Check for healthy backends -->
        <set-variable name="healthyBackends" value="@{
            var allBackends = new[] { "eastus", "westeurope" };
            var healthyList = new System.Collections.Generic.List<string>();
            
            foreach (var id in allBackends)
            {
                string cacheKey = "backend-health-" + id;
                string healthStatus;
                
                if (context.Cache.TryGetValue(cacheKey, out healthStatus))
                {
                    if (healthStatus == "healthy") healthyList.Add(id);
                }
                else
                {
                    healthyList.Add(id);
                }
            }
            
            return healthyList.Count > 0 ? healthyList.ToArray() : allBackends;
        }" />
        
        <!-- Geo-routing logic -->
        <set-variable name="preferredRegion" value="@{
            var clientRegion = context.Request.Headers.GetValueOrDefault("X-Azure-ClientRegion", "").ToLower();
            var europeanRegions = new[] { "eu", "europe", "uk", "de", "fr", "nl", "be", "it", "es", "pl", "se", "no", "dk", "fi", "at", "ch" };
            
            foreach (var region in europeanRegions)
            {
                if (clientRegion.Contains(region)) return "westeurope";
            }
            return "eastus";
        }" />
        
        <!-- Session affinity check -->
        <choose>
            <when condition="@(context.Request.Headers.GetValueOrDefault("Cookie","").Contains("APIM-Backend-Region"))">
                <set-variable name="backendRegion" value="@{
                    string cookie = context.Request.Headers.GetValueOrDefault("Cookie","");
                    var match = System.Text.RegularExpressions.Regex.Match(cookie, @"APIM-Backend-Region=([a-z]+)");
                    string requested = match.Success ? match.Groups[1].Value : null;
                    var healthy = (string[])context.Variables["healthyBackends"];
                    
                    if (requested != null && healthy.Contains(requested)) return requested;
                    
                    string preferred = (string)context.Variables["preferredRegion"];
                    return healthy.Contains(preferred) ? preferred : healthy[0];
                }" />
            </when>
            <otherwise>
                <set-variable name="backendRegion" value="@{
                    var healthy = (string[])context.Variables["healthyBackends"];
                    string preferred = (string)context.Variables["preferredRegion"];
                    return healthy.Contains(preferred) ? preferred : healthy[0];
                }" />
            </otherwise>
        </choose>
        
        <!-- Set backend based on region -->
        <set-backend-service base-url="@{
            string region = context.Variables.GetValueOrDefault<string>("backendRegion", "eastus");
            return region == "westeurope" 
                ? "https://{{WESTEUROPE_WEBAPP_HOSTNAME}}" 
                : "https://{{EASTUS_WEBAPP_HOSTNAME}}";
        }" />
        
        <set-header name="X-Backend-Region" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<string>("backendRegion", "eastus"))</value>
        </set-header>
    </inbound>
    
    <backend>
        <base />
    </backend>
    
    <outbound>
        <base />
        
        <!-- Circuit breaker -->
        <choose>
            <when condition="@(context.Response.StatusCode >= 500 || context.Response.StatusCode == 429)">
                <cache-store-value key="@("backend-health-" + context.Variables.GetValueOrDefault<string>("backendRegion"))" value="unhealthy" duration="30" />
            </when>
            <when condition="@(context.Response.StatusCode == 200)">
                <cache-store-value key="@("backend-health-" + context.Variables.GetValueOrDefault<string>("backendRegion"))" value="healthy" duration="30" />
            </when>
        </choose>
        
        <!-- Session cookie -->
        <set-header name="Set-Cookie" exists-action="append">
            <value>@{
                string region = context.Variables.GetValueOrDefault<string>("backendRegion", "eastus");
                return $"APIM-Backend-Region={region}; Path=/; Max-Age=86400; HttpOnly; Secure; SameSite=Lax";
            }</value>
        </set-header>
        
        <set-header name="X-Served-By-Region" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<string>("backendRegion", "eastus"))</value>
        </set-header>
    </outbound>
    
    <on-error>
        <base />
        <cache-store-value key="@("backend-health-" + context.Variables.GetValueOrDefault<string>("backendRegion", "eastus"))" value="unhealthy" duration="30" />
    </on-error>
</policies>
'''
  }
  dependsOn: [
    namedValuePrimaryHost
    namedValueSecondaryHost
  ]
}

// Product for the API
resource product 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apim
  name: 'bing-grounding-mcp'
  properties: {
    displayName: 'Bing Grounding MCP'
    description: 'Multi-region Bing Grounding MCP service'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  parent: product
  name: api.name
}

// Subscription for the product
resource subscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  parent: apim
  name: 'default-subscription'
  properties: {
    displayName: 'Default Subscription'
    scope: '/products/${product.id}'
    state: 'active'
  }
}

// Outputs
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimMcpEndpoint string = '${apim.properties.gatewayUrl}/bing-grounding/mcp'
output primaryBackendId string = backendPrimary.id
output secondaryBackendId string = backendSecondary.id
