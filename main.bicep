// ============================================================================
// main.bicep — AI Landing Zone (orchestrator)
// ----------------------------------------------------------------------------
// This file is the "platform" in a platform-vs-workload separation. It
// creates a resource group and the generic, reusable resources typically
// needed by an AI application:
//   • Monitoring (Log Analytics + Application Insights)
//   • Storage Account (with a blob container)
//   • Key Vault (RBAC mode)
//   • Azure AI Foundry account + project + model deployments
//   • Azure Container Registry
//   • Azure Container Apps Environment (without the app itself)
//   • A user-assigned managed identity for the app in step 2
//   • Role assignments that grant the identity access to the resources above
//
// The application itself (Container App and any app-specific resources) is
// deployed separately in "step 2" and consumes outputs from this deployment.
// ============================================================================

targetScope = 'subscription'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Short, non-identifying name of the workload. Used in every resource name; choose a globally unique value without personal or customer information. 3-16 lowercase letters or digits. Example: "exampleworkload".')
@minLength(3)
@maxLength(16)
param workloadName string

@description('Azure region where every resource is deployed.')
param location string = 'swedencentral'

@description('Environment label. Use "demo" for this template — it signals to readers that the deployment is a learning artefact, not a real PoC heading to prod.')
@allowed([
  'demo'
  'poc'
  'dev'
])
param environment string = 'demo'

@description('Global TPM quota (thousands of tokens per minute) per model deployment.')
@minValue(1)
@maxValue(500)
param modelCapacity int = 30

@description('Tags applied to every resource in the landing zone.')
param tags object = {
  environment: environment
  workload: workloadName
  managedBy: 'bicep'
}

// ----------------------------------------------------------------------------
// Variables — naming convention
// ----------------------------------------------------------------------------
// Pattern: resources are named "{prefix}-{workloadName}-{environment}", or
// "{prefix}{workloadName}{environment}" for resources with strict rules
// (Storage Account, Container Registry — lowercase letters and digits only,
// no hyphens). No hashes — names should be human-readable.
//
// NOTE: The Storage Account, Key Vault, Container Registry, and Foundry's
// customSubDomainName must be globally unique in Azure. Choose an available,
// non-identifying workloadName (for example, "exampleworkload").

var nameSuffix = '${workloadName}-${environment}'   // for hyphenated names
var nameSuffixCompact = '${workloadName}${environment}' // for strict names

var resourceGroupName = 'rg-${nameSuffix}'

var names = {
  logAnalytics:           'log-${nameSuffix}'
  appInsights:            'appi-${nameSuffix}'
  storageAccount:         'st${nameSuffixCompact}'
  keyVault:               'kv-${nameSuffix}'
  foundryAccount:         'aif-${nameSuffix}'
  foundryProject:         'proj-${workloadName}'
  containerRegistry:      'cr${nameSuffixCompact}'
  containerAppsEnv:       'cae-${nameSuffix}'
  managedIdentity:        'id-${nameSuffix}'
}

// ----------------------------------------------------------------------------
// Resource group
// ----------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ----------------------------------------------------------------------------
// Modules — called in order to make dependencies clear
// ----------------------------------------------------------------------------
// Monitoring first — all other modules send diagnostics there.

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    location: location
    tags: tags
  }
}

// Storage, Key Vault, Container Registry, and Foundry can be deployed in
// parallel — they have no dependencies on each other, only on monitoring.

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    storageAccountName: names.storageAccount
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    keyVaultName: names.keyVault
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module containerRegistry 'modules/containerRegistry.bicep' = {
  name: 'containerRegistry'
  scope: rg
  params: {
    acrName: names.containerRegistry
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  scope: rg
  params: {
    foundryAccountName: names.foundryAccount
    foundryProjectName: names.foundryProject
    workloadName: workloadName
    location: location
    tags: tags
    modelCapacity: modelCapacity
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    appInsightsResourceId: monitoring.outputs.appInsightsResourceId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// The Container Apps Environment needs the Log Analytics workspace shared
// key — the module reads it through an `existing` reference.

module containerAppsEnv 'modules/containerAppsEnv.bicep' = {
  name: 'containerAppsEnv'
  scope: rg
  params: {
    containerAppsEnvironmentName: names.containerAppsEnv
    location: location
    tags: tags
    logAnalyticsWorkspaceName: monitoring.outputs.workspaceName
  }
}

// The Managed Identity is independent — the app in step 2 binds it to its Container App.

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    managedIdentityName: names.managedIdentity
    location: location
    tags: tags
  }
}

// RBAC last — all target resources must exist first.

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  scope: rg
  params: {
    principalId: identity.outputs.managedIdentityPrincipalId
    foundryAccountName: foundry.outputs.foundryAccountName
    foundryProjectName: foundry.outputs.foundryProjectName
    storageAccountName: storage.outputs.storageAccountName
    keyVaultName: keyvault.outputs.keyVaultName
    acrName: containerRegistry.outputs.acrName
  }
}

// ----------------------------------------------------------------------------
// Outputs — consumed by the app deployment in step 2
// ----------------------------------------------------------------------------

output resourceGroupName string = rg.name

output foundryAccountEndpoint string = foundry.outputs.foundryAccountEndpoint
output foundryAccountName string = foundry.outputs.foundryAccountName
output foundryProjectName string = foundry.outputs.foundryProjectName

output storageAccountName string = storage.outputs.storageAccountName
output storageBlobEndpoint string = storage.outputs.blobEndpoint
output invoiceContainerName string = storage.outputs.containerName

output keyVaultUri string = keyvault.outputs.keyVaultUri
output keyVaultName string = keyvault.outputs.keyVaultName

output containerRegistryLoginServer string = containerRegistry.outputs.acrLoginServer
output containerRegistryName string = containerRegistry.outputs.acrName

output containerAppsEnvironmentId string = containerAppsEnv.outputs.containerAppsEnvironmentId
output containerAppsEnvironmentName string = containerAppsEnv.outputs.containerAppsEnvironmentName

output managedIdentityResourceId string = identity.outputs.managedIdentityResourceId
output managedIdentityClientId string = identity.outputs.managedIdentityClientId
output managedIdentityPrincipalId string = identity.outputs.managedIdentityPrincipalId

output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
