// ============================================================================
// Regional Resources Module
// Deploys AI Foundry + Project + App Service for a single region
// ============================================================================

param location string
param tags object
param foundryName string
param projectName string
param appServicePlanName string
param webAppName string
param regionIdentifier string  // 'primary' or 'secondary'
param pythonVersion string = '3.11'

// Model pool sizes (1 agent per model recommended for multi-region)
param agentPoolSizeGpt4o int = 1
param agentPoolSizeGpt41Mini int = 1
param agentPoolSizeGpt4 int = 0
param agentPoolSizeGpt35Turbo int = 0

// ============================================================================
// SUPPORTING RESOURCES
// ============================================================================

// Storage Account for AI Hub
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${uniqueString(resourceGroup().id, regionIdentifier)}'
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
  name: 'kv${uniqueString(resourceGroup().id, regionIdentifier)}'
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
  name: 'appi${uniqueString(resourceGroup().id, regionIdentifier)}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// AI FOUNDRY (Cognitive Services)
// ============================================================================

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
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

// Foundry Project
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

// ============================================================================
// MODEL DEPLOYMENTS (1 per model type - quotas are per region)
// ============================================================================

// GPT-4o deployment
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
      version: '2024-11-20'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

// GPT-4.1-mini deployment
resource deploymentGpt41Mini 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt41Mini > 0) {
  parent: foundry
  name: 'gpt-4.1-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4.1-mini'
      version: '2025-04-14'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt4o
  ]
}

// GPT-4 deployment
resource deploymentGpt4 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt4 > 0) {
  parent: foundry
  name: 'gpt-4'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4'
      version: '0613'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  dependsOn: [
    deploymentGpt41Mini
  ]
}

// GPT-3.5-turbo deployment
resource deploymentGpt35Turbo 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (agentPoolSizeGpt35Turbo > 0) {
  parent: foundry
  name: 'gpt-35-turbo'
  sku: {
    name: 'GlobalStandard'
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

// ============================================================================
// APP SERVICE
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'appservice-${regionIdentifier}'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      appCommandLine: 'uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'AZURE_AI_PROJECT_ENDPOINT'
          value: 'https://${foundryName}.cognitiveservices.azure.com/api/projects/${projectName}'
        }
        {
          name: 'AZURE_AI_PROJECT_NAME'
          value: projectName
        }
        {
          name: 'AGENT_POOL_SIZE_GPT4O'
          value: string(agentPoolSizeGpt4o)
        }
        {
          name: 'AGENT_POOL_SIZE_GPT41MINI'
          value: string(agentPoolSizeGpt41Mini)
        }
      ]
    }
  }
}

// Role assignment for Web App to access Foundry
resource webAppCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webApp.id, foundry.id, 'Cognitive Services User')
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output foundryName string = foundry.name
output foundryEndpoint string = 'https://${foundry.properties.endpoint}'
output projectName string = project.name
output projectEndpoint string = 'https://${foundryName}.cognitiveservices.azure.com/api/projects/${projectName}'
output projectResourceId string = project.id
output webAppName string = webApp.name
output webAppHostName string = webApp.properties.defaultHostName
output webAppEndpoint string = 'https://${webApp.properties.defaultHostName}'
output webAppPrincipalId string = webApp.identity.principalId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
