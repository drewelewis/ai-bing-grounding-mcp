<#
.SYNOPSIS
    Deploy to Azure Container Apps environment

.DESCRIPTION
    Ensures Container Apps configuration is active and deploys using azd.

.PARAMETER EnvironmentName
    Name of the azd environment (default: uses current environment)

.EXAMPLE
    .\deploy-containerapp.ps1
#>

param(
    [string]$EnvironmentName = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n🚀 Deploying to Azure Container Apps..." -ForegroundColor Cyan

$azureYaml = "azure.yaml"
$containerAppYaml = "azure-containerapp.yaml"

# Check if current azure.yaml is App Service version
$currentContent = Get-Content $azureYaml -Raw
$isAppService = $currentContent -match "host:\s*appservice"

if ($isAppService) {
    # Check if we have a Container Apps backup
    if (Test-Path $containerAppYaml) {
        Write-Host "📝 Switching to Container Apps config..." -ForegroundColor Yellow
        Copy-Item $containerAppYaml $azureYaml -Force
    } else {
        Write-Host "❌ Container Apps config not found. Restore from git:" -ForegroundColor Red
        Write-Host "   git checkout azure.yaml" -ForegroundColor Gray
        exit 1
    }
}

# Select environment if specified
if ($EnvironmentName) {
    Write-Host "🔧 Selecting environment: $EnvironmentName" -ForegroundColor Yellow
    azd env select $EnvironmentName
}

# Deploy
Write-Host "`n🚀 Running azd up..." -ForegroundColor Cyan
azd up

Write-Host "`n✅ Container Apps deployment complete!" -ForegroundColor Green
