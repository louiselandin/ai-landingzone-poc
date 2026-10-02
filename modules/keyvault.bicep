// ============================================================================
// keyvault.bicep — Key Vault in RBAC mode
// ----------------------------------------------------------------------------
// What: Creates a Key Vault for application secrets. In RBAC mode, access is
//       controlled by Azure RBAC roles rather than legacy access policies.
// Why: Every application needs a place to store sensitive values (such as
//      third-party API keys or database passwords during migration). Key Vault
//      is the standard choice on Azure.
// Educational note: Purge protection is permanent once enabled — it cannot be
//                    disabled. It is intentionally OFF in this PoC template
//                    so resources can be deleted and redeployed without
//                    waiting for a purge. Enable it in production.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
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
// Resources
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
    // RBAC mode — no access policies. Roles are managed in modules/rbac.bicep.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Intentionally OFF for the demo — enablePurgeProtection is omitted to
    // simplify teardown and redeployment. In production, set
    // enablePurgeProtection: true.
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

@description('Key Vault DNS URI, e.g. https://kv-exampleworkload-demo.vault.azure.net/.')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault resource ID.')
output keyVaultId string = keyVault.id
