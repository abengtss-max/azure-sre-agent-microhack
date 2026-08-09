using './main.bicep'

param namePrefix = 'aetherion'
// Provide a strong password at deploy time, e.g. via -p pgAdminPassword=... or an env lookup.
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD', '')
// Object ID of the deploying user/service principal (az ad signed-in-user).
param deployerObjectId = readEnvironmentVariable('DEPLOYER_OBJECT_ID', '')
param apimPublisherEmail = 'sre-team@aetherion.example'
param apimPublisherName = 'Aetherion AirOps SRE'
// Consumption = provisions in ~1-2 min (recommended for the workshop). Developer = 30-45 min.
param apimSkuName = 'Consumption'
param aksNodeCount = 3
param aksNodeVmSize = 'Standard_D4s_v5'
