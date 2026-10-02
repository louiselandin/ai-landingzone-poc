// ============================================================================
// main.bicepparam — example parameters for main.bicep
// ----------------------------------------------------------------------------
// Change workloadName for each deployment. The other parameters have sensible defaults.
// ============================================================================

using 'main.bicep'

// CHANGE ME: set your workload name (3–16 lowercase letters or digits).
// Choose an available, non-identifying name because the Storage Account, Key
// Vault, and Container Registry names must be globally unique in Azure.
param workloadName = 'exampleworkload'

// Explicitly set to 'demo' — this template is for learning, not delivery.
// "demo" appears in all resource names to make this clear.
// For a real PoC, change it to 'poc'.
param environment = 'demo'

// Reduced to 10 TPMx1000 for testing — increase to 30+ when quota allows.
param modelCapacity = 10

// Keep the defaults active — uncomment only if you need to change a value:
// param location = 'swedencentral'
// param tags = {
//   environment: 'demo'
//   workload: 'exampleworkload'
//   managedBy: 'bicep'
//   costCenter: 'ai-platform'
// }
