// ============================================================================
// storage.bicep — Storage Account + "invoices" blob container
// ----------------------------------------------------------------------------
// What: Creates a StorageV2 account, a blob service, and a container named
//       "invoices". Sends all blob diagnostics to Log Analytics.
// Why: Most AI applications need storage for documents, images, or embedding
//      source files. Entra authentication is enforced (allowSharedKeyAccess
//      = false) so the app in step 2 must use its managed identity — no
//      "account keys in app settings."
// Educational note: "invoices" is a generic example. A real template would
//                    choose a container name specific to the workload.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Globally unique storage account name (3-24 chars, lowercase + digits).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object

@description('Resource ID of the Log Analytics workspace to send diagnostics to.')
param logAnalyticsWorkspaceId string

@description('Name of the blob container to create.')
param containerName string = 'invoices'

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // No shared keys — the app MUST authenticate with Entra/Managed Identity.
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      // The PoC is open. In production, set defaultAction: 'Deny' and allowlist
      // the Container App Environment's outbound IP, or use private endpoints.
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessTier: 'Hot'
  }
}

// The blob service is a child of the account — it always exists implicitly,
// but is declared explicitly here so diagnostics and containers can be attached.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource invoicesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Diagnostics — the "allLogs" category includes StorageRead/Write/Delete.
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: blobService
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

@description('Storage account name.')
output storageAccountName string = storageAccount.name

@description('Storage account resource ID.')
output storageAccountId string = storageAccount.id

@description('Primary blob endpoint URI.')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Name of the blob container created by this module.')
output containerName string = invoicesContainer.name
