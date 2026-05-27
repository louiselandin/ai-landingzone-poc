// ============================================================================
// storage.bicep — Storage Account + blob-container "invoices"
// ----------------------------------------------------------------------------
// Vad: Skapar ett StorageV2-konto, en blob-tjänst, och en container kallad
//      "invoices". Skickar all blob-diagnostik till Log Analytics.
// Varför: De flesta AI-applikationer behöver lagring för dokument, bilder
//         eller embeddings-källfiler. Vi tvingar Entra-autentisering
//         (allowSharedKeyAccess = false) så att appen i steg 2 måste använda
//         sin managed identity — inga "konton-nycklar i appsettings".
// Pedagogisk not: "Invoices" är ett exempelnamn som matchar "fuelinvoice"-
//                 demon. I en riktig template skulle container-namnet vara
//                 en parameter.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
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
// Resurser
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
    // Inga delade nycklar — appen MÅSTE autentisera med Entra/Managed Identity.
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      // PoC kör öppet. I prod sätter man defaultAction: 'Deny' och vitlistar
      // Container App-miljöns utgående IP eller använder private endpoints.
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessTier: 'Hot'
  }
}

// Blob-tjänsten är ett "barn" till kontot — den finns alltid implicit, men vi
// deklarerar den explicit så att vi kan hänga diagnostik och containers på den.
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

// Diagnostik — kategorin "allLogs" inkluderar StorageRead/Write/Delete.
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
