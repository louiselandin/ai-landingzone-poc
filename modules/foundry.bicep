// ============================================================================
// foundry.bicep — Azure AI Foundry account + project + model deployments
// ----------------------------------------------------------------------------
// What: Creates:
//       1. A "Foundry account" (Microsoft.CognitiveServices/accounts with
//          kind 'AIServices') — the multi-model resource.
//       2. Model deployments for several GPT and embedding models.
//       3. A Foundry project under the account.
//       4. An Application Insights connection to stream Foundry telemetry.
//       5. Diagnostic settings that send data to Log Analytics.
// Why: Foundry is the hub of an AI application. The account provides model
//      inference endpoints; the project is the workspace for agents,
//      evaluations, and knowledge connections.
// Educational note: A Foundry account IS a Cognitive Services account with
//                    kind = 'AIServices'. It is not a separate platform, but
//                    an Azure resource that brings together multiple Azure AI
//                    services. Model deployments must be created sequentially
//                    to avoid race conditions, so @batchSize(1) is used.
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Name of the Foundry (AIServices) account.')
param foundryAccountName string

@description('Name of the Foundry project (e.g. proj-exampleworkload).')
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
// Variables — model deployments
// ----------------------------------------------------------------------------
// This list is looped over sequentially with @batchSize(1) below.
// TODO: Validate model versions against
//       https://learn.microsoft.com/azure/ai-services/openai/concepts/models
//       before deploying in a region other than swedencentral.

var modelDeployments = [
  {
    name: 'gpt-4o-mini'
    modelName: 'gpt-4o-mini'
    modelVersion: '2024-07-18'
    skuName: 'GlobalStandard'
    capacity: modelCapacity
  }
  {
    // TODO: Validate the latest version for o4-mini.
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
    // NOTE: Only GlobalStandard is supported for embedding models in swedencentral.
    skuName: 'GlobalStandard'
    capacity: modelCapacity
  }
]

// ----------------------------------------------------------------------------
// Resources
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
    // customSubDomainName is required for Entra authentication. Use the
    // account name as the subdomain — it is deterministic and guaranteed to
    // be unique (with the same uniqueness guarantee as the account name).
    customSubDomainName: foundryAccountName
    // No API keys — Entra authentication only.
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    // Required to create projects under the account (Foundry feature).
    allowProjectManagement: true
  }
}

// Model deployments — @batchSize(1) forces Bicep to create them one at a
// time, avoiding race conditions that can occur when creating multiple
// deployments in parallel on the same Cognitive Services account.
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
    // The default content filter (Microsoft.DefaultV2) is applied
    // automatically when raiPolicyName is omitted.
  }
}]

// Foundry project — a child of the account.
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
  // The project can be created immediately, but for readability we wait until
  // the models are ready. dependsOn is not technically required, but makes
  // the dependency explicit to the reader.
  dependsOn: [
    models
  ]
}

// Project-level Application Insights connection. Foundry uses it to send
// agent traces and evaluation results to Application Insights.
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

// Account diagnostics — the Audit and RequestResponse categories are the
// most useful for troubleshooting model calls.
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

@description('Foundry account public endpoint, e.g. https://aif-exampleworkload-demo.cognitiveservices.azure.com/.')
output foundryAccountEndpoint string = foundryAccount.properties.endpoint

@description('Foundry project name.')
output foundryProjectName string = foundryProject.name

@description('Foundry project resource ID.')
output foundryProjectId string = foundryProject.id
