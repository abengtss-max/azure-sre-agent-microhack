#Requires -Version 7.0
# Aetherion AirOps - grant the SRE Agent's managed identity the one permission it
# needs beyond the defaults: writing API Management policy.
#
# The agent's user-assigned identity is created with the agent, not by the
# infrastructure deployment, so this cannot live in main.bicep. Without it the
# agent can diagnose an edge policy fault but cannot remediate it, and the major
# incident in Challenge 7 has no reachable fix.

param(
    [string]$AgentName
)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env.aetherion.json'
if (-not (Test-Path $envFile)) { throw "State file not found. Run 01-deploy-infra.ps1 first." }
$state = Get-Content $envFile -Raw | ConvertFrom-Json
$rg = $state.resourceGroup

if (-not $AgentName) {
    $agents = az resource list -g $rg --resource-type 'Microsoft.App/agents' --query "[].name" -o tsv
    $AgentName = @($agents)[0]
    if (-not $AgentName) {
        throw "No Microsoft.App/agents resource found in '$rg'. Create the SRE Agent first (Challenge 1), then re-run."
    }
}

Write-Host "Agent: $AgentName"

$identityId = az resource show -g $rg -n $AgentName --resource-type Microsoft.App/agents `
    --api-version 2026-01-01 --query "properties.actionConfiguration.identity" -o tsv
if (-not $identityId) { throw "The agent has no managed identity set. Complete the agent setup first." }

$principalId = az identity show --ids $identityId --query principalId -o tsv
Write-Host "Identity principal: $principalId"

$scope = az resource show -g $rg -n $state.apimName --resource-type Microsoft.ApiManagement/service --query id -o tsv

$existing = az role assignment list --assignee-object-id $principalId --scope $scope `
    --query "[?roleDefinitionName=='API Management Service Contributor'] | length(@)" -o tsv
if ([int]$existing -gt 0) {
    Write-Host "  already granted - nothing to do."
    return
}

az role assignment create `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --role 'API Management Service Contributor' `
    --scope $scope --output none

Write-Host "  granted 'API Management Service Contributor' on $($state.apimName)."
Write-Host "  Scoped to the API Management service only, not the resource group."
Write-Host "  Role assignments can take a couple of minutes to take effect."
