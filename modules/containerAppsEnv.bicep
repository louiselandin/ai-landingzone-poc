// ============================================================================
// containerAppsEnv.bicep — Azure Container Apps Environment
// ----------------------------------------------------------------------------
// Vad: Skapar ett managed environment för Container Apps. SJÄLVA Container
//      App-resursen skapas INTE här — den hör till workload-deployen i steg 2.
// Varför: Environment:et är den nätverks- och loggdomän som flera Container
//         Apps kan dela. Vi vill att plattformen äger environment:et så att
//         appar i steg 2 enkelt kan plugga in i samma logg-pipeline.
// Pedagogisk not: Vi använder Consumption-only (inga workload profiles).
//                 Inget VNet — appen får offentliga utgående IPs. För prod
//                 vill man typiskt köra Workload Profiles + VNet + private
//                 endpoints till de andra resurserna.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('Container Apps Environment name.')
param containerAppsEnvironmentName string

@description('Azure region for the environment.')
param location string

@description('Tags applied to the environment.')
param tags object

@description('Name of the Log Analytics workspace to ship app logs to. Must live in the same resource group.')
param logAnalyticsWorkspaceName string

// ----------------------------------------------------------------------------
// Existerande resurser
// ----------------------------------------------------------------------------
// Vi behöver workspace:ets customerId och primarySharedKey för att koppla
// app-loggar. Genom att referera till workspace:et som "existing" här slipper
// vi skicka känsliga keys mellan moduler.

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ----------------------------------------------------------------------------
// Resurser
// ----------------------------------------------------------------------------

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    // Endast Consumption-profil — ingen Dedicated/Premium.
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // Inget VNet — appen är publik. internal:false betyder publikt ingress.
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Container Apps Environment name.')
output containerAppsEnvironmentName string = environment.name

@description('Container Apps Environment resource ID — appen i steg 2 refererar till denna.')
output containerAppsEnvironmentId string = environment.id
