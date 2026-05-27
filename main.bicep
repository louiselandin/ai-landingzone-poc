// ============================================================================
// main.bicep — AI Landing Zone (orkestrator)
// ----------------------------------------------------------------------------
// Den här filen är "plattformen" i en plattform-vs-workload-uppdelning. Den
// skapar en resursgrupp och alla generiska, återanvändbara resurser som en
// AI-applikation typiskt behöver:
//   • Monitoring (Log Analytics + Application Insights)
//   • Storage Account (med en blob-container)
//   • Key Vault (RBAC-läge)
//   • Azure AI Foundry-konto + projekt + modelldeployments
//   • Azure Container Registry
//   • Azure Container Apps Environment (utan själva appen)
//   • En user-assigned managed identity för appen i steg 2
//   • Role assignments som ger identiteten rätt att läsa allt ovan
//
// Själva applikationen (Container App + eventuella appspecifika resurser)
// deployas separat i "steg 2" och konsumerar outputs från denna deployment.
// ============================================================================

targetScope = 'subscription'

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('Short name of the workload. Used in every resource name, so keep it lowercase, unique-enough (some resources are globally unique — include a team/tenant marker if needed) and 3-16 chars. Example: "branslefakturor".')
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
// Variabler — namnstandard
// ----------------------------------------------------------------------------
// Mönster: alla resurser namnges som "{prefix}-{workloadName}-{environment}",
// eller "{prefix}{workloadName}{environment}" för resurser med strikta regler
// (Storage Account, Container Registry — bara små bokstäver och siffror,
// inga bindestreck). Inga hashar — namnen ska vara läsbara för människor.
//
// OBS: Storage Account, Key Vault, Container Registry och Foundrys
// customSubDomainName är GLOBALT unika i Azure. Välj ett workloadName
// som är unikt nog (t.ex. "acme-fuelinv" snarare än bara "test").

var nameSuffix = '${workloadName}-${environment}'   // för bindestreck-namn
var nameSuffixCompact = '${workloadName}${environment}' // för strikta namn

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
// Resursgrupp
// ----------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ----------------------------------------------------------------------------
// Moduler — anropas i ordning så att beroenden är tydliga
// ----------------------------------------------------------------------------
// Monitoring först — alla andra moduler skickar diagnostik dit.

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

// Storage, Key Vault, Container Registry och Foundry kan deployas parallellt
// — de har inga inbördes beroenden, bara på monitoring.

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

// Container Apps Environment behöver Log Analytics-nyckeln (delad nyckel) —
// modulen läser den via en `existing`-referens.

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

// Managed Identity är fristående — appen i steg 2 binder den till sin Container App.

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    managedIdentityName: names.managedIdentity
    location: location
    tags: tags
  }
}

// RBAC sist — alla målresurser måste existera först.

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
// Outputs — konsumeras av app-deployen i steg 2
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
