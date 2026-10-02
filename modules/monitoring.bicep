// ============================================================================
// monitoring.bicep — Log Analytics + Application Insights
// ----------------------------------------------------------------------------
// What: Creates a Log Analytics workspace and a workspace-based Application
//       Insights instance connected to it.
// Why: Observability is fundamental to an AI landing zone. Foundry, Container
//      Apps, Storage, Key Vault, and ACR all send diagnostics to the same
//      workspace, providing one place to troubleshoot with KQL. The
//      application in step 2 uses Application Insights for traces, metrics,
//      and Foundry telemetry.
// Educational note: Workspace-based Application Insights stores data in
//                    Log Analytics instead of a separate database. This has
//                    been the standard since 2020.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Name of the Application Insights component.')
param appInsightsName string

@description('Azure region for both resources.')
param location string

@description('Tags applied to both resources.')
param tags object

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    // 30 days is the default retention and is sufficient for a PoC. For
    // production, consider increasing it to 90+ days and linking dedicated
    // archive storage.
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Workspace-based Application Insights — data is stored in Log Analytics above.
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('Resource ID of the Log Analytics workspace.')
output workspaceId string = logAnalytics.id

@description('Name of the Log Analytics workspace. The Container Apps Environment uses it to read shared keys.')
output workspaceName string = logAnalytics.name

@description('Connection string for Application Insights. Used by the application in step 2.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Resource ID of the Application Insights component. Used by the Foundry project connection.')
output appInsightsResourceId string = appInsights.id
