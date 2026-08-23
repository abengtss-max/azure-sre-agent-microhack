metadata description = 'Aetherion AirOps - Azure SRE Agent MicroHack environment. Provisions AKS, ACR, APIM, PostgreSQL Flexible Server, Redis, Log Analytics, Application Insights and Managed Grafana. Teaching environment only - not production hardened.'

@description('Prefix used for all resource names. Lowercase letters and numbers only.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'aetherion'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('PostgreSQL administrator login name.')
param pgAdminLogin string = 'aetherionadmin'

@description('PostgreSQL administrator password.')
@secure()
param pgAdminPassword string

@description('Object ID (principal) of the person/service running the deployment. Used to grant Grafana Admin.')
param deployerObjectId string

@description('Publisher email for API Management.')
param apimPublisherEmail string = 'sre-team@aetherion.example'

@description('Publisher name for API Management.')
param apimPublisherName string = 'Aetherion AirOps SRE'

@description('Backend URL that APIM forwards to (the AKS gateway public IP). Updated after the app is deployed.')
param gatewayBackendUrl string = 'http://aetherion-gateway.invalid'

@description('Number of AKS worker nodes.')
@minValue(1)
@maxValue(5)
param aksNodeCount int = 2

@description('VM size for AKS worker nodes.')
param aksNodeVmSize string = 'Standard_D4s_v5'

@description('Kubernetes version for AKS. The deploy script resolves the current stable (default) GA version at runtime and passes it in, so this literal is only a fallback.')
param kubernetesVersion string = '1.33'

@description('APIM SKU. Consumption provisions in ~1-2 min (best for a disposable workshop); Developer takes 30-45 min.')
@allowed([
  'Consumption'
  'Developer'
])
param apimSkuName string = 'Consumption'

var suffix = uniqueString(resourceGroup().id)
var acrName = toLower('${namePrefix}acr${suffix}')
var aksName = '${namePrefix}-aks'
var lawName = '${namePrefix}-law'
var appiName = '${namePrefix}-appi'
var pgName = toLower('${namePrefix}-pg-${suffix}')
var apimName = toLower('${namePrefix}-apim-${suffix}')
var grafanaName = take(toLower('${namePrefix}graf${suffix}'), 23)
var amwName = take(toLower('${namePrefix}-amw-${suffix}'), 44)

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var grafanaAdminRoleId = '22926164-76b3-42b3-bc55-97df8dab3e41'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    IngestionMode: 'LogAnalytics'
  }
}

// Container Insights gives pod state but not a CPU time series, and several
// challenges ask the agent to correlate CPU over a window. Managed Prometheus
// is linked to the cluster in 01-deploy-infra.ps1.
resource amw 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: amwName
  location: location
  properties: {}
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: aksName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: '${namePrefix}-aks'
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    // Declared explicitly because ARM reapplies the template as authored: when this
    // block was omitted, redeploying an existing cluster reset networkPlugin to the
    // kubenet default. Keep these matching the running cluster.
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'none'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      podCidr: '10.244.0.0/16'
      outboundType: 'loadBalancer'
      loadBalancerSku: 'standard'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        count: aksNodeCount
        vmSize: aksNodeVmSize
        mode: 'System'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: true
        minCount: aksNodeCount
        maxCount: aksNodeCount + 2
      }
    ]
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: pgAdminLogin
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
    authConfig: {
      passwordAuth: 'Enabled'
      activeDirectoryAuth: 'Disabled'
    }
  }
}

resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'aetherion'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource pgFirewallAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Query Store turns "this query is probably slow" into per-query runtime evidence,
// which is the next thing an SRE reaches for after seeing the server saturated.
// Chained on the firewall rule and on each other: the server rejects concurrent
// configuration writes.
resource pgQueryStore 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'pg_qs.query_capture_mode'
  properties: {
    value: 'TOP'
    source: 'user-override'
  }
  dependsOn: [pgFirewallAzure]
}

resource pgWaitSampling 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'pgms_wait_sampling.query_capture_mode'
  properties: {
    value: 'ALL'
    source: 'user-override'
  }
  dependsOn: [pgQueryStore]
}

var openApiSpec = {
  openapi: '3.0.1'
  info: {
    title: 'Aetherion AirOps API'
    version: '1.0'
  }
  paths: {
    '/api/status': { get: { operationId: 'getStatus', summary: 'Ops status', responses: { '200': { description: 'ok' } } } }
    '/api/flights': { get: { operationId: 'getFlights', summary: 'Flight board', responses: { '200': { description: 'ok' } } } }
    '/api/crew': { get: { operationId: 'getCrew', summary: 'Crew roster', responses: { '200': { description: 'ok' } } } }
    '/api/book': { post: { operationId: 'postBook', summary: 'Create booking', responses: { '200': { description: 'ok' } } } }
    '/api/bookings/count': { get: { operationId: 'getBookingsCount', summary: 'Booking count', responses: { '200': { description: 'ok' } } } }
    '/api/baggage/throughput': { get: { operationId: 'getBaggage', summary: 'Baggage throughput', responses: { '200': { description: 'ok' } } } }
    '/api/telemetry': { post: { operationId: 'postTelemetry', summary: 'Ingest telemetry', responses: { '200': { description: 'ok' } } } }
  }
}

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: apimSkuName
    capacity: apimSkuName == 'Consumption' ? 0 : 1
  }
  properties: {
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

resource apimApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'aetherion'
  properties: {
    displayName: 'Aetherion AirOps API'
    path: 'aetherion'
    protocols: [ 'https' ]
    serviceUrl: gatewayBackendUrl
    subscriptionRequired: true
    format: 'openapi+json'
    value: string(openApiSpec)
  }
}

resource apimProduct 'Microsoft.ApiManagement/service/products@2023-05-01-preview' = {
  parent: apim
  name: 'aetherion-ops'
  properties: {
    displayName: 'Aetherion Operations'
    description: 'Operational APIs for Aetherion AirOps.'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource apimProductApi 'Microsoft.ApiManagement/service/products/apis@2023-05-01-preview' = {
  parent: apimProduct
  name: apimApi.name
}

resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  parent: apim
  name: 'aetherion-ops-sub'
  properties: {
    displayName: 'Aetherion Ops Subscription'
    scope: apimProduct.id
    state: 'active'
  }
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  sku: { name: 'Standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    apiKey: 'Enabled'
    publicNetworkAccess: 'Enabled'
  }
}

resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, grafana.id, monitoringReaderRoleId)
  scope: resourceGroup()
  properties: {
    principalId: grafana.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource grafanaAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deployerObjectId, grafanaAdminRoleId)
  scope: grafana
  properties: {
    principalId: deployerObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', grafanaAdminRoleId)
    principalType: 'User'
  }
}

// -----------------------------------------------------------------------------
// Major-incident alerting (Challenge 7)
// A fixed-severity (Sev 1) Azure Monitor alert on Application Insights failed
// requests. The SRE Agent response plan attendees build in Challenge 6 filters
// on Severity = Sev1, so this rule must be authored at that exact severity to be
// caught. The action group makes the alert fully functional in the portal.
// -----------------------------------------------------------------------------
resource incidentActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${namePrefix}-incident-ag'
  location: 'global'
  properties: {
    groupShortName: 'AetherIncid'
    enabled: true
  }
}

resource incidentAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-major-incident'
  location: 'global'
  properties: {
    description: 'Sev1 major incident: Application Insights failed requests spiking (Challenge 7 cross-tier cascade). Triggers the SRE Agent response plan filtered to Sev1.'
    severity: 1
    enabled: true
    scopes: [ appi.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedRequests'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: 25
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: incidentActionGroup.id
      }
    ]
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output aksName string = aks.name
output aksNodeResourceGroup string = aks.properties.nodeResourceGroup
output pgServerName string = pg.name
output pgFqdn string = pg.properties.fullyQualifiedDomainName
output pgAdminLogin string = pgAdminLogin
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output appInsightsName string = appi.name
output logAnalyticsName string = law.name
output logAnalyticsId string = law.id
output azureMonitorWorkspaceId string = amw.id
output grafanaName string = grafana.name
output grafanaEndpoint string = grafana.properties.endpoint
output incidentAlertName string = incidentAlert.name
output incidentActionGroupName string = incidentActionGroup.name
