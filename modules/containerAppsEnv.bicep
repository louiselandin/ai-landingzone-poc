// ============================================================================
// containerAppsEnv.bicep — Azure Container Apps Environment
// ----------------------------------------------------------------------------
// What: Creates a managed environment for Container Apps. The Container App
//       resource itself is NOT created here — it belongs to the workload
//       deployment in step 2.
// Why: The environment is the network and logging domain shared by multiple
//      Container Apps. The platform owns it so apps in step 2 can easily join
//      the same logging pipeline.
// Educational note: Uses Consumption only (no workload profiles).
//                    No VNet — the app gets public outbound IPs. For
//                    production, Workload Profiles, a VNet, and private
//                    endpoints to the other resources are typical.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
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
// Existing resources
// ----------------------------------------------------------------------------
// The workspace's customerId and primarySharedKey are needed to connect app
// logs. Referencing the workspace as "existing" here avoids passing sensitive
// keys between modules.

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ----------------------------------------------------------------------------
// Resources
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
    // Consumption profile only — no Dedicated/Premium.
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // No VNet — the app is public. internal:false means public ingress.
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Container Apps Environment name.')
output containerAppsEnvironmentName string = environment.name

@description('Container Apps Environment resource ID — the app in step 2 references this.')
output containerAppsEnvironmentId string = environment.id
