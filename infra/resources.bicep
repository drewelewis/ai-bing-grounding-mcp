param location string
param tags object
param apimServiceName string
param foundryName string
param projectName string
param containerAppEnvName string
param containerAppName string
param containerRegistryName string
param containerImage string

// Model pool sizes from .env (passed via main.bicep)
param agentPoolSizeGpt41 int = 0
param agentPoolSizeGpt5 int = 0
param agentPoolSizeGpt5Mini int = 0
param agentPoolSizeGpt5Nano int = 0
param agentPoolSizeGpt4o int = 0
param agentPoolSizeGpt4 int = 0
param agentPoolSizeGpt35Turbo int = 0

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

// Model Deployments - Deploy each model conditionally based on pool size
// GPT-4.1
resource deploymentGpt41 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt41 > 0) {
  parent: foundry
  name: 'gpt-4.1'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1'
      version: '2025-04-14'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

// GPT-5
resource deploymentGpt5 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt5 > 0) {
  parent: foundry
  name: 'gpt-5'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5'
      version: '2025-08-07'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt41
  ]
}

// GPT-5-mini
resource deploymentGpt5Mini 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt5Mini > 0) {
  parent: foundry
  name: 'gpt-5-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt5
  ]
}

// GPT-5-nano
resource deploymentGpt5Nano 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt5Nano > 0) {
  parent: foundry
  name: 'gpt-5-nano'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-nano'
      version: '2025-08-07'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt5Mini
  ]
}

// GPT-4o
resource deploymentGpt4o 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt4o > 0) {
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
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt5Nano
  ]
}

// GPT-4
resource deploymentGpt4 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt4 > 0) {
  parent: foundry
  name: 'gpt-4'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4'
      version: 'turbo-2024-04-09'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt4o
  ]
}

// GPT-3.5-turbo
resource deploymentGpt35Turbo 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt35Turbo > 0) {
  parent: foundry
  name: 'gpt-35-turbo'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '0125'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt4
  ]
}

// Bing Grounding Resource - MUST BE CREATED MANUALLY
// Due to API limitations, create via Azure Portal:
// https://portal.azure.com/#create/Microsoft.BingGroundingSearch
// Resource must be in the same resource group as the AI Foundry project
// The agents will automatically connect to it at runtime

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
            {
              name: 'AZURE_REGION'
              value: location
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            name: 'cpu-scaling'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
          {
            name: 'memory-scaling'
            custom: {
              type: 'memory'
              metadata: {
                type: 'Utilization'
                value: '80'
              }
            }
          }
        ]
      }
    }
  }
}

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
    serviceUrl: 'https://${containerApp.properties.configuration.ingress.fqdn}'
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
    description: 'Query with Bing grounding and citations. Supports gpt-5, gpt-5-mini, gpt-4o, gpt-4, gpt-35-turbo.'
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
          description: 'AI model to use (gpt-5, gpt-5-mini, gpt-4o, gpt-4, gpt-35-turbo)'
        }
      ]
    }
  }
}

// Grant primary Container App managed identity access to Foundry Project
// Use Azure AI User role which has Microsoft.CognitiveServices/* dataActions (includes agents/read)
resource roleAssignmentPrimary 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, containerApp.id, 'AzureAIUser')
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d') // Azure AI User
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Bing Grounding role assignments not needed - built-in tool

// Outputs
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output foundryName string = foundry.name
output projectName string = project.name
output projectEndpoint string = 'https://${foundryName}.services.ai.azure.com/api/projects/${projectName}'
output projectResourceId string = project.id
// Output deployed model names (dynamically built from conditional deployments)
output gpt4oDeploymentName string = agentPoolSizeGpt4o > 0 ? 'gpt-4o' : (agentPoolSizeGpt41 > 0 ? 'gpt-4.1' : 'gpt-4o')
output deployedModels array = concat(
  agentPoolSizeGpt41 > 0 ? ['gpt-4.1'] : [],
  agentPoolSizeGpt5 > 0 ? ['gpt-5'] : [],
  agentPoolSizeGpt5Mini > 0 ? ['gpt-5-mini'] : [],
  agentPoolSizeGpt5Nano > 0 ? ['gpt-5-nano'] : [],
  agentPoolSizeGpt4o > 0 ? ['gpt-4o'] : [],
  agentPoolSizeGpt4 > 0 ? ['gpt-4'] : [],
  agentPoolSizeGpt35Turbo > 0 ? ['gpt-35-turbo'] : []
)
output containerRegistryName string = containerRegistry.name
output containerRegistryEndpoint string = containerRegistry.properties.loginServer
output containerAppEndpoint string = containerApp.properties.configuration.ingress.fqdn
output containerAppName string = containerAppName
