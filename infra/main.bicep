targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the resource group. If empty, a name will be generated.')
param resourceGroupName string = ''

@description('Name of the API Management service. If empty, a name will be generated.')
param apimServiceName string = ''

@description('Name of the Microsoft Foundry resource. If empty, a name will be generated.')
param foundryName string = ''

@description('Name of the Foundry project. If empty, a name will be generated.')
param projectName string = ''

@description('Name of the Container App Environment. If empty, a name will be generated.')
param containerAppEnvName string = ''

@description('Name of the Container App. If empty, a name will be generated.')
param containerAppName string = ''

@description('Name of the Container Registry. If empty, a name will be generated.')
param containerRegistryName string = ''

@description('Container image to deploy. If empty, uses default.')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Number of Container App instances to deploy for load balancing')
@minValue(1)
@maxValue(10)
param containerAppInstances int = 3

// Generate resource group name if not provided
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

var finalResourceGroupName = !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}bing-grounding-mcp-${environmentName}'
var finalApimName = !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
var finalFoundryName = !empty(foundryName) ? foundryName : '${abbrs.cognitiveServicesAccounts}foundry-${resourceToken}'
var finalProjectName = !empty(projectName) ? projectName : '${abbrs.cognitiveServicesAccounts}proj-${resourceToken}'
var finalContainerAppEnvName = !empty(containerAppEnvName) ? containerAppEnvName : '${abbrs.appManagedEnvironments}${resourceToken}'
var finalContainerAppName = !empty(containerAppName) ? containerAppName : '${abbrs.appContainerApps}${resourceToken}'
var finalContainerRegistryName = !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: finalResourceGroupName
  location: location
  tags: tags
}

// Deploy main resources into the resource group
module resources './resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    tags: tags
    apimServiceName: finalApimName
    foundryName: finalFoundryName
    projectName: finalProjectName
    containerAppEnvName: finalContainerAppEnvName
    containerAppName: finalContainerAppName
    containerRegistryName: finalContainerRegistryName
    containerImage: containerImage
    containerAppInstances: containerAppInstances
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_APIM_NAME string = resources.outputs.apimName
output AZURE_APIM_GATEWAY_URL string = resources.outputs.apimGatewayUrl
output AZURE_FOUNDRY_NAME string = resources.outputs.foundryName
output AZURE_AI_PROJECT_NAME string = resources.outputs.projectName
output AZURE_AI_PROJECT_ENDPOINT string = resources.outputs.projectEndpoint
output AZURE_AI_PROJECT_RESOURCE_ID string = resources.outputs.projectResourceId
output AZURE_OPENAI_MODEL_GPT4O string = resources.outputs.gpt4oDeploymentName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.containerRegistryEndpoint
output AZURE_CONTAINER_REGISTRY_NAME string = resources.outputs.containerRegistryName
output AZURE_CONTAINER_APP_ENDPOINT string = resources.outputs.containerAppEndpoint
output AZURE_CONTAINER_APP_NAME string = resources.outputs.containerAppName
output AZURE_BING_CONNECTION_ID string = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${rg.name}/providers/Microsoft.CognitiveServices/accounts/${finalFoundryName}/projects/${finalProjectName}/connections/default-bing'
