// ============================================================================
// identity.bicep — User-assigned Managed Identity
// ----------------------------------------------------------------------------
// Vad: Skapar en user-assigned managed identity (UAMI).
// Varför: Container Appen i steg 2 binder den här identiteten till sig och
//         autentiserar mot Foundry, Storage, Key Vault och ACR med den.
//         En UAMI är "portabel" — den överlever om vi river och deployar
//         om appen, vilket gör att RBAC-rolltilldelningar (som tar
//         minuter att propagera) bara behöver göras en gång.
// Pedagogisk not: Skillnad mot system-assigned: en SAMI lever och dör med
//                 sin förälder-resurs. En UAMI lever fristående och kan
//                 bindas till flera resurser. För landing zones är UAMI
//                 nästan alltid rätt val.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('Name of the user-assigned managed identity.')
param managedIdentityName string

@description('Azure region for the identity.')
param location string

@description('Tags applied to the identity.')
param tags object

// ----------------------------------------------------------------------------
// Resurser
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
