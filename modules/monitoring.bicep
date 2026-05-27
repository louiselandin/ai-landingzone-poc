// ============================================================================
// monitoring.bicep — Log Analytics + Application Insights
// ----------------------------------------------------------------------------
// Vad: Skapar en Log Analytics workspace och en workspace-baserad Application
//      Insights-instans kopplad till den.
// Varför: I en AI Landing Zone är observability fundamentalt. Foundry,
//         Container Apps, Storage, Key Vault och ACR skickar alla diagnostik
//         till samma workspace, vilket ger en enda plats att felsöka i KQL.
//         Application Insights används av själva applikationen i steg 2 för
//         traces, metrics och Foundry-telemetri.
// Pedagogisk not: "Workspace-baserad" AppInsights betyder att data lagras i
//                 Log Analytics istället för en egen separat databas. Det är
//                 nya standarden sedan 2020.
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
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
// Resurser
// ----------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    // 30 dagar är default-retention och räcker gott för en PoC. För prod
    // kan man vilja höja till 90+ dagar och länka en dedikerad arkivlagring.
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
    // Workspace-baserad AppInsights — data hamnar i Log Analytics ovan.
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

@description('Name of the Log Analytics workspace. Used by Container Apps Env to read shared keys.')
output workspaceName string = logAnalytics.name

@description('Connection string for Application Insights. Used by the application in step 2.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Resource ID of the Application Insights component. Used by the Foundry project connection.')
output appInsightsResourceId string = appInsights.id
