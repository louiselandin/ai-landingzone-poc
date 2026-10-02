// ============================================================================
// containerRegistry.bicep — Azure Container Registry (ACR)
// ----------------------------------------------------------------------------
// What: Creates a Basic SKU ACR without an admin user (Entra authentication
//       only). Sends diagnostics to Log Analytics.
// Why: The Container App image in step 2 needs to be stored somewhere. ACR is
//      the standard choice and integrates with Container Apps through the
//      AcrPull role on the managed identity bound to the app.
// Educational note: The Basic SKU is sufficient for a PoC. Premium is
//                    preferable for production workloads with many readers
//                    or geo-replication.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
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
// Resources
// ----------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    // No admin user — enforce Entra/Managed Identity (AcrPull role).
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
