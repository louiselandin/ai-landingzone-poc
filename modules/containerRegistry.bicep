// ============================================================================
// containerRegistry.bicep — Azure Container Registry (ACR)
// ----------------------------------------------------------------------------
// Vad: Skapar ett ACR av SKU Basic utan admin user (alltså bara Entra-
//      autentisering). Skickar diagnostik till Log Analytics.
// Varför: Container App-imagen i steg 2 behöver lagras någonstans. ACR är
//         standardvalet och integrerar med Container Apps via AcrPull-rollen
//         på den managed identity som binds till appen.
// Pedagogisk not: Basic-SKU räcker för PoC. För prod-workloads med många
//                 läsare eller geo-replikering vill man ha Premium.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('ACR name (5-50 chars, lowercase + digits).')
@minLength(5)
@maxLength(50)
param acrName string

@description('Azure region for the registry.')
param location string

@description('Tags applied to the registry.')
param tags object

@description('Resource ID of the Log Analytics workspace to send diagnostics to.')
param logAnalyticsWorkspaceId string

// ----------------------------------------------------------------------------
// Resurser
// ----------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    // Ingen admin user — vi tvingar Entra/Managed Identity (AcrPull-rollen).
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    anonymousPullEnabled: false
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: acr
  name: 'to-loganalytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('ACR name.')
output acrName string = acr.name

@description('ACR login server FQDN, e.g. xxxx.azurecr.io.')
output acrLoginServer string = acr.properties.loginServer

@description('ACR resource ID.')
output acrId string = acr.id
