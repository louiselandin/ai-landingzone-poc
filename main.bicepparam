// ============================================================================
// main.bicepparam — exempelparametrar för main.bicep
// ----------------------------------------------------------------------------
// Ändra workloadName per deploy. Övriga parametrar har vettiga defaults.
// ============================================================================

using 'main.bicep'

// CHANGE ME: ange ditt workload-namn (3–16 tecken, små bokstäver/siffror).
// Välj något unikt nog — t.ex. "<team>-<funktion>" — då Storage Account, Key
// Vault och Container Registry måste vara globalt unika i hela Azure.
param workloadName = 'branslefakturor'

// Explicit satt till 'demo' — den här templaten används för att lära ut, inte
// för att leverera. "demo" hamnar i alla resursnamn så att det syns tydligt.
// För en riktig PoC: byt till 'poc'.
param environment = 'demo'

// Sänkt till 10 TPMx1000 för test — höj till 30+ när kvoten räcker.
param modelCapacity = 10

// Lämna defaults aktiva — avkommentera bara om du behöver byta värde:
// param location = 'swedencentral'
// param tags = {
//   environment: 'demo'
//   workload: 'branslefakturor'
//   managedBy: 'bicep'
//   costCenter: 'ai-platform'
// }
