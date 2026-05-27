// ============================================================================
// keyvault.bicep — Key Vault i RBAC-läge
// ----------------------------------------------------------------------------
// Vad: Skapar ett Key Vault som lagrar applikationens secrets. RBAC-läge
//      betyder att åtkomst styrs av Azure RBAC-roller, inte legacy access
//      policies.
// Varför: Alla applikationer behöver någonstans att lagra känsliga värden
//         (API-nycklar till tredjepartstjänster, databaslösenord vid
//         migration, etc.). Key Vault är standardvalet på Azure.
// Pedagogisk not: "Purge protection" är permanent när den är på — kan inte
//                 stängas av. Vi har den AV i den här PoC-templaten så att
//                 man kan riva ner och deploya om utan att vänta på purge.
//                 I prod ska den vara PÅ.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('Key Vault name (3-24 chars, letters/digits/hyphens, must start with a letter).')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure region for the Key Vault.')
param location string

@description('Tags applied to the Key Vault.')
param tags object

@description('Resource ID of the Log Analytics workspace to send diagnostics to.')
param logAnalyticsWorkspaceId string

// ----------------------------------------------------------------------------
// Resurser
// ----------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    // RBAC-läge — inga access policies. Roller hanteras i modules/rbac.bicep.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Avsiktligt AV för demo — vi utelämnar enablePurgeProtection helt så att
    // riv/omdeploy går smidigt. I prod: sätt enablePurgeProtection: true.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: keyVault
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

@description('Key Vault name.')
output keyVaultName string = keyVault.name

@description('Key Vault DNS URI, e.g. https://kv-branslefakturor-demo.vault.azure.net/.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault resource ID.')
output keyVaultId string = keyVault.id
