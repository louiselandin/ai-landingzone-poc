// ============================================================================
// foundry.bicep — Azure AI Foundry-konto + projekt + modelldeployments
// ----------------------------------------------------------------------------
// Vad: Skapar
//        1. Ett "Foundry-konto" (Microsoft.CognitiveServices/accounts av
//           kind 'AIServices') — själva multi-modell-resursen.
//        2. Modelldeployments för flera GPT- och embedding-modeller.
//        3. Ett Foundry-projekt under kontot.
//        4. En Application Insights-koppling så att Foundry-telemetri
//           strömmar dit.
//        5. Diagnostic settings till Log Analytics.
// Varför: Foundry är navet i en AI-applikation. Kontot ger inferens-endpoints
//         för modellerna; projektet är arbetsytan där agenter, evals och
//         knowledge connections lever.
// Pedagogisk not: Foundry-kontot ÄR ett Cognitive Services-konto, bara med
//                 kind = 'AIServices'. Det är ingen separat plattform — bara
//                 en Azure-resurs som "fakulterar" en mängd Azure AI-tjänster.
//                 Modelldeployments måste skapas sekventiellt (race conditions
//                 vid parallell deployment) — vi använder @batchSize(1).
// ============================================================================

// ----------------------------------------------------------------------------
// Parametrar
// ----------------------------------------------------------------------------

@description('Name of the Foundry (AIServices) account.')
param foundryAccountName string

@description('Name of the Foundry project (e.g. proj-branslefakturor).')
param foundryProjectName string

@description('Workload name — used for the project displayName/description defaults.')
param workloadName string

@description('Azure region for the Foundry account and project.')
param location string

@description('Tags applied to Foundry resources.')
param tags object

@description('Global TPM capacity (thousands of tokens per minute) per model deployment.')
@minValue(1)
@maxValue(500)
param modelCapacity int

@description('Resource ID of the Log Analytics workspace to send diagnostics to.')
param logAnalyticsWorkspaceId string

@description('Resource ID of the Application Insights component used for the project connection.')
param appInsightsResourceId string

@description('Application Insights connection string — used as the connection metadata.')
param appInsightsConnectionString string

@description('Display name for the Foundry project shown in the portal.')
param projectDisplayName string = 'Project ${workloadName}'

@description('Description for the Foundry project shown in the portal.')
param projectDescription string = 'AI Foundry project for workload ${workloadName}.'

// ----------------------------------------------------------------------------
// Variabler — modelldeployments
// ----------------------------------------------------------------------------
// En lista som loopas sekventiellt med @batchSize(1) längre ner.
// TODO: validera versionsnummer mot
//       https://learn.microsoft.com/azure/ai-services/openai/concepts/models
//       innan deploy i annan region än swedencentral.

var modelDeployments = [
  {
    name: 'gpt-4o-mini'
    modelName: 'gpt-4o-mini'
    modelVersion: '2024-07-18'
    skuName: 'GlobalStandard'
    capacity: modelCapacity
  }
  {
    // TODO: validera senaste version för o4-mini.
    name: 'o4-mini'
    modelName: 'o4-mini'
    modelVersion: '2025-04-16'
    skuName: 'GlobalStandard'
    capacity: modelCapacity
  }
  {
    name: 'text-embedding-3-small'
    modelName: 'text-embedding-3-small'
    modelVersion: '1'
    // OBS: i swedencentral stöds bara GlobalStandard för embedding-modellerna.
    skuName: 'GlobalStandard'
    capacity: modelCapacity
  }
]

// ----------------------------------------------------------------------------
// Resurser
// ----------------------------------------------------------------------------

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryAccountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // customSubDomainName krävs för Entra-autentisering. Vi använder
    // accountname som subdomän — deterministiskt och garanterat unikt
    // (samma unikhetsgarantier som account-namnet självt).
    customSubDomainName: foundryAccountName
    // Inga API-nycklar — bara Entra-autentisering.
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    // Krävs för att skapa projekt under kontot (Foundry-feature).
    allowProjectManagement: true
  }
}

// Modelldeployments — @batchSize(1) tvingar Bicep att skapa dem en i taget,
// vilket undviker race conditions som annars uppstår när man försöker skapa
// flera deployments parallellt på samma Cognitive Services-konto.
@batchSize(1)
resource models 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [for m in modelDeployments: {
  parent: foundryAccount
  name: m.name
  sku: {
    name: m.skuName
    capacity: m.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: m.modelName
      version: m.modelVersion
    }
    // Default content filter (Microsoft.DefaultV2) appliceras automatiskt
    // när raiPolicyName utelämnas.
  }
}]

// Foundry-projektet — barn till kontot.
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectDisplayName
    description: projectDescription
  }
  // Projekt kan skapas direkt — men för läsbarhet väntar vi tills modellerna
  // är klara. dependsOn behövs inte tekniskt men gör beroendet explicit för
  // läsaren.
  dependsOn: [
    models
  ]
}

// Application Insights-koppling på projekt-nivå. Foundry använder den här
// kopplingen för att skicka agent-traces och evaluation-resultat till AppI.
resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: 'appinsights'
  properties: {
    category: 'AppInsights'
    target: appInsightsResourceId
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: appInsightsConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsightsResourceId
    }
  }
}

// Diagnostik på kontot — kategorierna Audit och RequestResponse är de mest
// värdefulla för att felsöka modellanrop.
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: foundryAccount
  name: 'to-loganalytics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Audit'
        enabled: true
      }
      {
        category: 'RequestResponse'
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

@description('Foundry account name.')
output foundryAccountName string = foundryAccount.name

@description('Foundry account resource ID.')
output foundryAccountId string = foundryAccount.id

@description('Foundry account public endpoint, e.g. https://aif-branslefakturor-demo.cognitiveservices.azure.com/.')
output foundryAccountEndpoint string = foundryAccount.properties.endpoint

@description('Foundry project name.')
output foundryProjectName string = foundryProject.name

@description('Foundry project resource ID.')
output foundryProjectId string = foundryProject.id
