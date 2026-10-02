// ============================================================================
// rbac.bicep — Role assignments for the application's managed identity
// ----------------------------------------------------------------------------
// What: Assigns five built-in roles to the user-assigned managed identity so
//       it can do exactly what it needs — no more:
//        • Cognitive Services OpenAI User   → Foundry account
//        • Azure AI User                    → Foundry-projektet
//        • Storage Blob Data Contributor    → Storage Account
//        • Key Vault Secrets User           → Key Vault
//        • AcrPull                          → Container Registry
// Why: The platform owns role assignments so the app in step 2 can focus on
//      its own code — it inherits the right access through its identity binding.
// Educational note: roleAssignments need a deterministic GUID name to be
//                    idempotent. The guid(scope, principal, role) pattern
//                    returns the same name every time, avoiding "duplicate
//                    role assignment" errors on redeployment.
//                    The person running the deployment must have User Access
//                    Administrator (or Owner) on the resource group.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Object/principal ID of the managed identity to grant roles to.')
param principalId string

@description('Foundry account name (parent of the project).')
param foundryAccountName string

@description('Foundry project name (child of the account).')
param foundryProjectName string

@description('Storage account name.')
param storageAccountName string

@description('Key Vault name.')
param keyVaultName string

@description('ACR name.')
param acrName string

// ----------------------------------------------------------------------------
// Variables — built-in role definition IDs
// ----------------------------------------------------------------------------
// Source: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles

var roleIds = {
  cognitiveServicesOpenAiUser:  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  azureAiUser:                  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
  storageBlobDataContributor:   'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  keyVaultSecretsUser:          '4633458b-17de-408a-b874-0445c86b69e6'
  acrPull:                      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

// ----------------------------------------------------------------------------
// Existing resources — roles are assigned at their scope
// ----------------------------------------------------------------------------

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

// ----------------------------------------------------------------------------
// Role assignments
// ----------------------------------------------------------------------------

resource roleAssignmentFoundryAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, principalId, roleIds.cognitiveServicesOpenAiUser)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.cognitiveServicesOpenAiUser)
  }
}

resource roleAssignmentFoundryProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(foundryProject.id, principalId, roleIds.azureAiUser)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.azureAiUser)
  }
}

resource roleAssignmentStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, roleIds.storageBlobDataContributor)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataContributor)
  }
}

resource roleAssignmentKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, roleIds.keyVaultSecretsUser)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsUser)
  }
}

resource roleAssignmentAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, principalId, roleIds.acrPull)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.acrPull)
  }
}
