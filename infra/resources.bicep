param location string
param tags object
param apimServiceName string
param foundryName string
param projectName string
param containerAppEnvName string
param containerAppName string
param containerRegistryName string
param containerImage string
param containerAppInstances int

// Storage Account for AI Hub
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Key Vault for AI Hub
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// Microsoft Foundry Resource (replaces AI Hub + Azure OpenAI)
// This is the new GA resource type for Azure AI Foundry
// Includes built-in Azure OpenAI capabilities
resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    // Required to work in AI Foundry portal
    allowProjectManagement: true
    // Defines developer API endpoint subdomain
    customSubDomainName: foundryName
    // Use Azure AD authentication instead of keys
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// Foundry Project (replaces hub-based AI Project)
// Projects group inputs/outputs for one use case, including files and conversation history
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  name: projectName
  parent: foundry
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Deploy GPT-4o model (supports Bing grounding in Agent Service)
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundry
  name: 'gpt-4o'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
  }
}

// Bing Grounding Search Resource
// Will be created via postprovision script and connected to Foundry
// Bicep deployment currently experiencing API issues

// Container App Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Primary Container App (azd deploys to this one)
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'api'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8989
        transport: 'auto'
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'bing-grounding-api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'AZURE_AI_PROJECT_ENDPOINT'
              value: 'https://${foundry.properties.endpoint}'
            }
            {
              name: 'AZURE_AI_PROJECT_NAME'
              value: project.name
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// Additional Container App instances for load balancing (1 and 2)
resource containerAppReplicas 'Microsoft.App/containerApps@2023-05-01' = [for i in range(1, containerAppInstances - 1): {
  name: '${containerAppName}-${i}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8989
        transport: 'auto'
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'bing-grounding-api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'AZURE_AI_PROJECT_ENDPOINT'
              value: 'https://${foundry.properties.endpoint}'
            }
            {
              name: 'AZURE_AI_PROJECT_NAME'
              value: project.name
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}]

// API Management Service
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'Contoso'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// API in APIM
resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'bing-grounding-api'
  properties: {
    displayName: 'Bing Grounding API'
    apiRevision: '1'
    subscriptionRequired: true
    path: 'bing-grounding'
    protocols: ['https']
  }
}

// Health endpoint operation
resource healthOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
    description: 'Health check endpoint'
  }
}

// Bing grounding endpoint operation
resource bingGroundingOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'bing-grounding'
  properties: {
    displayName: 'Bing Grounding'
    method: 'POST'
    urlTemplate: '/bing-grounding'
    description: 'Query with Bing grounding and citations'
    request: {
      queryParameters: [
        {
          name: 'query'
          type: 'string'
          required: true
          description: 'The query to process'
        }
      ]
    }
  }
}

// Grant primary Container App managed identity access to Foundry Project
resource roleAssignmentPrimary 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, containerApp.id, 'AzureAIDeveloper')
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee') // Azure AI Developer
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant additional Container Apps managed identity access to Foundry Project
resource roleAssignmentReplicas 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(1, containerAppInstances - 1): {
  name: guid(project.id, containerAppReplicas[i - 1].id, 'AzureAIDeveloper')
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee') // Azure AI Developer
    principalId: containerAppReplicas[i - 1].identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Bing Grounding role assignments not needed - built-in tool

// Outputs
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output foundryName string = foundry.name
output projectName string = project.name
// Foundry endpoint - HTTPS format for GA projects (SDK beta12+)
output projectEndpoint string = 'https://${foundry.properties.endpoint}'
output projectResourceId string = project.id
output gpt4oDeploymentName string = gpt4oDeployment.name
output containerRegistryName string = containerRegistry.name
output containerRegistryEndpoint string = containerRegistry.properties.loginServer
output containerAppEndpoint string = containerApp.properties.configuration.ingress.fqdn
output containerAppName string = containerAppName
