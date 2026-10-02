// ============================================================================
// identity.bicep — User-assigned Managed Identity
// ----------------------------------------------------------------------------
// What: Creates a user-assigned managed identity (UAMI).
// Why: The Container App in step 2 binds to this identity and uses it to
//      authenticate to Foundry, Storage, Key Vault, and ACR. A UAMI is
//      "portable" — it survives app deletion and redeployment, so RBAC role
//      assignments (which can take minutes to propagate) only need to be
//      created once.
// Educational note: Unlike a system-assigned managed identity, a SAMI lives
//                    and dies with its parent resource. A UAMI exists
//                    independently and can be bound to multiple resources.
//                    UAMIs are almost always the right choice for landing zones.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Name of the user-assigned managed identity.')
param managedIdentityName string

@description('Azure region for the identity.')
param location string

@description('Tags applied to the identity.')
param tags object

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Managed identity name.')
output managedIdentityName string = managedIdentity.name

@description('Managed identity resource ID. Bind this to the Container App in step 2.')
output managedIdentityResourceId string = managedIdentity.id

@description('Managed identity client ID. Use as AZURE_CLIENT_ID env var in the app.')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity object/principal ID. Used by rbac.bicep for role assignments.')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
