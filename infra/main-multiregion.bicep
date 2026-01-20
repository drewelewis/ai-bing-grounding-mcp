targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for shared resources (APIM, etc.)')
param location string

@description('Secondary region for App Service and AI Foundry')
param secondaryLocation string = 'westeurope'

@description('Name of the resource group. If empty, a name will be generated.')
param resourceGroupName string = ''

@description('Name of the secondary resource group. If empty, a name will be generated.')
param secondaryResourceGroupName string = ''

@description('Name of the API Management service. If empty, a name will be generated.')
param apimServiceName string = ''

@description('Name of the primary region Microsoft Foundry resource. If empty, a name will be generated.')
param foundryNamePrimary string = ''

@description('Name of the secondary region Microsoft Foundry resource. If empty, a name will be generated.')
param foundryNameSecondary string = ''

@description('Name of the primary Foundry project. If empty, a name will be generated.')
param projectNamePrimary string = ''

@description('Name of the secondary Foundry project. If empty, a name will be generated.')
param projectNameSecondary string = ''

@description('Name of the primary App Service Plan. If empty, a name will be generated.')
param appServicePlanNamePrimary string = ''

@description('Name of the secondary App Service Plan. If empty, a name will be generated.')
param appServicePlanNameSecondary string = ''

@description('Name of the primary Web App. If empty, a name will be generated.')
param webAppNamePrimary string = ''

@description('Name of the secondary Web App. If empty, a name will be generated.')
param webAppNameSecondary string = ''

// Model pool sizes - 1 agent per model per region is recommended
@description('Number of GPT-4o agents to create per region')
param agentPoolSizeGpt4o int = 1

@description('Number of GPT-4.1-mini agents to create per region')
param agentPoolSizeGpt41Mini int = 1

@description('Number of GPT-4 agents to create per region')
param agentPoolSizeGpt4 int = 0

@description('Number of GPT-3.5-turbo agents to create per region')
param agentPoolSizeGpt35Turbo int = 0

// Generate resource names
var abbrs = loadJsonContent('./abbreviations.json')
var resourceTokenPrimary = toLower(uniqueString(subscription().id, environmentName, location))
var resourceTokenSecondary = toLower(uniqueString(subscription().id, environmentName, secondaryLocation))
var tags = { 
  'azd-env-name': environmentName
  'multi-region': 'true'
}

// Primary region naming
var finalResourceGroupName = !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}bing-mcp-${environmentName}-${location}'
var finalApimName = !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceTokenPrimary}'
var finalFoundryNamePrimary = !empty(foundryNamePrimary) ? foundryNamePrimary : '${abbrs.cognitiveServicesAccounts}foundry-${resourceTokenPrimary}'
var finalProjectNamePrimary = !empty(projectNamePrimary) ? projectNamePrimary : '${abbrs.cognitiveServicesAccounts}proj-${resourceTokenPrimary}'
var finalAppServicePlanNamePrimary = !empty(appServicePlanNamePrimary) ? appServicePlanNamePrimary : '${abbrs.webServerFarms}${resourceTokenPrimary}'
var finalWebAppNamePrimary = !empty(webAppNamePrimary) ? webAppNamePrimary : '${abbrs.webSitesAppService}${resourceTokenPrimary}'

// Secondary region naming
var finalSecondaryResourceGroupName = !empty(secondaryResourceGroupName) ? secondaryResourceGroupName : '${abbrs.resourcesResourceGroups}bing-mcp-${environmentName}-${secondaryLocation}'
var finalFoundryNameSecondary = !empty(foundryNameSecondary) ? foundryNameSecondary : '${abbrs.cognitiveServicesAccounts}foundry-${resourceTokenSecondary}'
var finalProjectNameSecondary = !empty(projectNameSecondary) ? projectNameSecondary : '${abbrs.cognitiveServicesAccounts}proj-${resourceTokenSecondary}'
var finalAppServicePlanNameSecondary = !empty(appServicePlanNameSecondary) ? appServicePlanNameSecondary : '${abbrs.webServerFarms}${resourceTokenSecondary}'
var finalWebAppNameSecondary = !empty(webAppNameSecondary) ? webAppNameSecondary : '${abbrs.webSitesAppService}${resourceTokenSecondary}'

// ============================================================================
// PRIMARY REGION (East US)
// ============================================================================

resource rgPrimary 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: finalResourceGroupName
  location: location
  tags: union(tags, { 'region-role': 'primary' })
}

// Primary region AI Foundry + App Service
module resourcesPrimary './resources-region.bicep' = {
  name: 'resources-primary'
  scope: rgPrimary
  params: {
    location: location
    tags: union(tags, { 'region-role': 'primary' })
    foundryName: finalFoundryNamePrimary
    projectName: finalProjectNamePrimary
    appServicePlanName: finalAppServicePlanNamePrimary
    webAppName: finalWebAppNamePrimary
    regionIdentifier: 'primary'
    agentPoolSizeGpt4o: agentPoolSizeGpt4o
    agentPoolSizeGpt41Mini: agentPoolSizeGpt41Mini
    agentPoolSizeGpt4: agentPoolSizeGpt4
    agentPoolSizeGpt35Turbo: agentPoolSizeGpt35Turbo
  }
}

// ============================================================================
// SECONDARY REGION (West Europe)
// ============================================================================

resource rgSecondary 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: finalSecondaryResourceGroupName
  location: secondaryLocation
  tags: union(tags, { 'region-role': 'secondary' })
}

// Secondary region AI Foundry + App Service
module resourcesSecondary './resources-region.bicep' = {
  name: 'resources-secondary'
  scope: rgSecondary
  params: {
    location: secondaryLocation
    tags: union(tags, { 'region-role': 'secondary' })
    foundryName: finalFoundryNameSecondary
    projectName: finalProjectNameSecondary
    appServicePlanName: finalAppServicePlanNameSecondary
    webAppName: finalWebAppNameSecondary
    regionIdentifier: 'secondary'
    agentPoolSizeGpt4o: agentPoolSizeGpt4o
    agentPoolSizeGpt41Mini: agentPoolSizeGpt41Mini
    agentPoolSizeGpt4: agentPoolSizeGpt4
    agentPoolSizeGpt35Turbo: agentPoolSizeGpt35Turbo
  }
}

// ============================================================================
// SHARED RESOURCES (APIM - deployed to primary region but serves both)
// ============================================================================

module apim './apim-multiregion.bicep' = {
  name: 'apim'
  scope: rgPrimary
  params: {
    location: location
    tags: tags
    apimServiceName: finalApimName
    primaryWebAppHostname: resourcesPrimary.outputs.webAppHostName
    secondaryWebAppHostname: resourcesSecondary.outputs.webAppHostName
    primaryRegion: location
    secondaryRegion: secondaryLocation
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Global
output AZURE_LOCATION string = location
output AZURE_SECONDARY_LOCATION string = secondaryLocation
output AZURE_APIM_NAME string = apim.outputs.apimName
output AZURE_APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
output AZURE_MCP_ENDPOINT string = '${apim.outputs.apimGatewayUrl}/bing-grounding-mcp/mcp'

// Primary region
output AZURE_RESOURCE_GROUP_PRIMARY string = rgPrimary.name
output AZURE_FOUNDRY_NAME_PRIMARY string = resourcesPrimary.outputs.foundryName
output AZURE_AI_PROJECT_NAME_PRIMARY string = resourcesPrimary.outputs.projectName
output AZURE_AI_PROJECT_ENDPOINT_PRIMARY string = resourcesPrimary.outputs.projectEndpoint
output AZURE_WEBAPP_NAME_PRIMARY string = resourcesPrimary.outputs.webAppName
output AZURE_WEBAPP_ENDPOINT_PRIMARY string = resourcesPrimary.outputs.webAppEndpoint

// Secondary region
output AZURE_RESOURCE_GROUP_SECONDARY string = rgSecondary.name
output AZURE_FOUNDRY_NAME_SECONDARY string = resourcesSecondary.outputs.foundryName
output AZURE_AI_PROJECT_NAME_SECONDARY string = resourcesSecondary.outputs.projectName
output AZURE_AI_PROJECT_ENDPOINT_SECONDARY string = resourcesSecondary.outputs.projectEndpoint
output AZURE_WEBAPP_NAME_SECONDARY string = resourcesSecondary.outputs.webAppName
output AZURE_WEBAPP_ENDPOINT_SECONDARY string = resourcesSecondary.outputs.webAppEndpoint
