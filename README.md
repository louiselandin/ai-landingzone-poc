# AI Landing Zone — Bicep Demo Template

An educational Bicep template that creates the foundational infrastructure for an AI application on Azure. This is "step 1" — the application itself (Container App and any workload-specific resources) is deployed in "step 2".

---

## 1. What the template does

Creates a resource group and populates it with generic, reusable resources that most AI applications need:

| Resource | Role |
|---|---|
| Log Analytics workspace | Central logging hub — all resources send diagnostics here |
| Application Insights | Telemetry for the application and Foundry traces |
| Storage Account + `invoices` container | Storage for documents, images, and embedding source files |
| Key Vault (RBAC mode) | Secrets (such as API keys for external services) |
| Azure AI Foundry account (AIServices) | Multi-model inference endpoint |
| Foundry project (`proj-{workloadName}`) | Workspace for agents, evaluations, and connections |
| 3 model deployments | `gpt-4o-mini`, `o4-mini`, `text-embedding-3-small` (for `gpt-4o`, see the TODO in `modules/foundry.bicep`) |
| Application Insights connection on the project | Streams Foundry telemetry to App Insights |
| Container Registry (Basic) | Image registry for the Container App in step 2 |
| Container Apps Environment | Hosting environment for the Container App in step 2 |
| User-assigned Managed Identity | Identity that the Container App binds to and authenticates with |
| Role assignments | Grant the managed identity exactly the access it needs (least privilege) |

## 2. What the template **does not** do

- **No Container App** — that is step 2.
- **No VNet, subnets, private endpoints, Bastion, or NAT Gateway.** Everything runs publicly with Entra authentication.
- **No custom content filters** — Foundry's default filter, `Microsoft.DefaultV2`, is used automatically.
- **No workload-specific resources** — for example, SQL Server, Cosmos DB, or AI Search are left to step 2 if needed.
- **No App Configuration.**
- **No production hardening** — Key Vault purge protection is off, network ACLs allow all traffic, ACR uses the Basic SKU, etc.

## 3. Prerequisites

- Azure CLI installed (`az --version`).
- Bicep CLI installed (`az bicep install` or `az bicep upgrade`).
- Signed in with `az login` and the correct subscription selected with `az account set --subscription <id>`.
- The signed-in user has `Owner` at the subscription scope (simplest) **or** `Contributor` plus `User Access Administrator`. The latter is required to create the role assignments in `rbac.bicep`.
- Resource provider `Microsoft.App` registered:
  ```bash
  az provider register --namespace Microsoft.App
  ```

### Naming convention

Resources are named using the pattern `{prefix}-{workloadName}-{environment}` (or `{prefix}{workloadName}{environment}` for resources with strict naming rules, such as Storage Accounts and Container Registries). No random hashes are used — names are human-readable.

| Resource type | Pattern | Example (`workloadName`=`exampleworkload`, `env`=`demo`) |
|---|---|---|
| Resource group | `rg-{wl}-{env}` | `rg-exampleworkload-demo` |
| Foundry account | `aif-{wl}-{env}` | `aif-exampleworkload-demo` |
| Foundry project | `proj-{wl}` | `proj-exampleworkload` |
| Log Analytics | `log-{wl}-{env}` | `log-exampleworkload-demo` |
| Application Insights | `appi-{wl}-{env}` | `appi-exampleworkload-demo` |
| Storage Account | `st{wl}{env}` | `stexampleworkloaddemo` |
| Key Vault | `kv-{wl}-{env}` | `kv-exampleworkload-demo` |
| Container Registry | `cr{wl}{env}` | `crexampleworkloaddemo` |
| Container Apps Environment | `cae-{wl}-{env}` | `cae-exampleworkload-demo` |
| Managed Identity | `id-{wl}-{env}` | `id-exampleworkload-demo` |

**Note:** The Storage Account, Key Vault, Container Registry, and Foundry custom subdomain must be **globally unique** in Azure. Choose an available `workloadName` that does not contain personal or customer information. If a name is already taken, add an arbitrary suffix rather than identifying information. `workloadName` is limited to 3–16 characters because Storage Account names can be at most 24 characters.

**Tip:** The `environment` parameter accepts `demo`, `poc`, and `dev`. The **default is `demo`** — this clearly signals in resource names that the deployment is a learning artifact, not a real PoC intended for production.

## 4. How to deploy

```bash
# 1) Run a what-if first — this shows exactly what would be created or changed without deploying:
az deployment sub what-if \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam

# 2) Deploy:
az deployment sub create \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Change `workloadName` in `main.bicepparam` before running the command.

## 5. Resource details

- **Log Analytics + Application Insights** — the observability stack. Workspace-based Application Insights stores all data in Log Analytics, allowing you to correlate application traces with platform logs in KQL.
- **Storage Account** — StorageV2, LRS, TLS 1.2+, no public blob access, and **no shared keys** (Entra authentication is enforced). A blob container named `invoices` is created.
- **Key Vault** — RBAC mode (no access policies), 7-day soft delete, and purge protection disabled (for PoC cleanup).
- **Foundry account** — `Microsoft.CognitiveServices/accounts` with `kind: AIServices`. `disableLocalAuth: true` ensures that only Entra authentication works. `allowProjectManagement: true` allows projects to be created under the account.
- **Model deployments** — three deployments (`gpt-4o-mini`, `o4-mini`, `text-embedding-3-small`), created sequentially with `@batchSize(1)` to avoid race conditions. All use the same TPM capacity from the `modelCapacity` parameter. `gpt-4o` is commented out in `modules/foundry.bicep`, with instructions for requesting a quota increase.
- **Foundry project** — `proj-{workloadName}`. This is where agents, evaluations, and knowledge connections live.
- **App Insights connection on the project** — sends Foundry agent traces and evaluation results to Application Insights.
- **Container Registry** — Basic SKU, no admin user, Entra authentication only.
- **Container Apps Environment** — Consumption-only, no VNet, and application logs sent to Log Analytics.
- **Managed Identity** — user-assigned (UAMI). The Container App in step 2 binds this identity and gets access through it.
- **Role assignments** — five roles (see the role list in `modules/rbac.bicep`), all with deterministic GUID names so redeployments are idempotent.

## 6. Next steps

The outputs from `main.bicep` are the contract between the platform and the workload. Step 2 (the Container App deployment) consumes them:

- `containerAppsEnvironmentId` — where the app runs
- `managedIdentityResourceId` — the identity the app binds to
- `containerRegistryLoginServer` — where the app's image is pushed
- `foundryAccountEndpoint`, `foundryProjectName` — what the app uses to communicate with Foundry
- `storageBlobEndpoint`, `invoiceContainerName` — where the app reads and writes data
- `keyVaultUri` — where the app reads secrets
- `appInsightsConnectionString` — where the app sends telemetry

Any **workload-specific** resources (for example, a SQL Server for structured data or an AI Search instance for hybrid retrieval) are also created in step 2 — they do not belong in the landing zone because they are specific to the application.

## 7. How to tear down

```bash
az group delete --name rg-<workloadName>-<env> --yes --no-wait
```

**Important:** Azure soft-deletes Foundry accounts (Cognitive Services) by default — an account remains for about 48 hours after deletion. If you need to redeploy the template immediately with the same name, purge the account:

```bash
az cognitiveservices account purge \
  --location swedencentral \
  --name aif-<workloadName>-<env> \
  --resource-group rg-<workloadName>-<env>
```

(The resource group must be specified even if it has already been deleted — this is an Azure quirk.)

## 8. Common issues

| Symptom | Likely cause | Solution |
|---|---|---|
| `AuthorizationFailed` on the first deployment | The user lacks `User Access Administrator` at the subscription or resource group scope | Ask an Owner to grant the role, or deploy as an Owner |
| `ResourceDeploymentFailure` on a model deployment | The model is unavailable in `swedencentral`, or the version is invalid | Comment out the model in `modules/foundry.bicep` and try again. Validate against https://learn.microsoft.com/azure/ai-services/openai/concepts/models |
| `RoleAssignmentUpdateNotPermitted` | Attempting to change `principalType` or `principalId` on an existing role assignment | Delete the role assignment in the portal and redeploy |
| `StorageAccountAlreadyTaken` / `VaultAlreadyExists` | Someone else has already claimed the globally unique name in Azure | Choose a different `workloadName`; add an arbitrary suffix rather than a team or tenant identifier |
| Foundry project is created, but the app gets a 401 | RBAC has not propagated yet (about 5 minutes) | Wait and try again, or verify the assignment in the portal |
| `Microsoft.App not registered` | The resource provider is not registered | Run `az provider register --namespace Microsoft.App` and wait about 2 minutes |

## 9. Customize for your workload

The following are typically changed when cloning the template for a new AI application:

| What | Where | How |
|---|---|---|
| Workload name (appears in all resource names) | [`main.bicepparam`](main.bicepparam) | Change `param workloadName = '...'`; do not use personal or customer information |
| Environment label (`demo`/`poc`/`dev`/`test`/`prod`) | [`main.bicepparam`](main.bicepparam) | Change `param environment = '...'` |
| Models to deploy | [`modules/foundry.bicep`](modules/foundry.bicep) | Edit the `modelDeployments` array (`name`, `modelName`, `modelVersion`, `skuName`, `capacity`) |
| TPM capacity per model | [`main.bicepparam`](main.bicepparam) | Change `param modelCapacity = 10` |
| Blob container name | [`modules/storage.bicep`](modules/storage.bicep) | Change the default for `param containerName = 'invoices'` or promote it to a top-level parameter |
| Azure region | [`main.bicepparam`](main.bicepparam) | Uncomment and set `param location = '...'`. Note: the model list in `foundry.bicep` has been validated for `swedencentral`. |
| Tags | [`main.bicepparam`](main.bicepparam) | Uncomment the tags block |

To **add a new resource** (for example, AI Search or Cosmos DB), create a module under `modules/` and call it from `main.bicep`. Remember to add the corresponding role assignment in `modules/rbac.bicep` so the app's managed identity has access.

## 10. Estimated cost

Rough estimate for an **idle demo deployment** (no model calls or application traffic) in `swedencentral`:

| Resource | Monthly cost (approx., SEK) |
|---|---|
| Log Analytics (PerGB2018, no incoming data) | ~0 |
| Application Insights (workspace-based, no data) | ~0 |
| Storage Account (StorageV2 LRS, empty) | <5 |
| Key Vault (Standard, no operations) | <5 |
| Container Registry (Basic) | ~50 |
| Container Apps Environment (Consumption, no app) | ~0 |
| Managed Identity | 0 |
| Foundry account (AIServices) | 0 base fee — pay per token for usage |
| **Idle total** | **~50–70 SEK/month** |

Actual usage adds model tokens (gpt-4o-mini is approximately 0.0015 USD per 1,000 input tokens), Container App runtime, Log Analytics ingestion, and stored blobs/images. For production volumes, use the Azure Pricing Calculator with your expected usage.

## 11. Educational note — platform vs. workload

The Cloud Adoption Framework distinguishes between the **platform** (owned by a central team and shared or used consistently by multiple workloads) and the **workload** (owned by a product team and specific to an application).

This template is **the platform component for a single AI workload**: it is generic enough for most AI applications (they all need Foundry, storage, secrets, observability, a hosting environment, and an identity), but it is not a complete application.

In practice, an AI platform team would:

1. Run **this template** for each new AI workload (step 1).
2. Hand off the outputs to the application team, which deploys its Container App, databases, connection strings in Key Vault, etc. (step 2).

This separation lets the platform team upgrade the baseline (for example, switch from Basic to Premium ACR or add private endpoints) without modifying any individual app's code — as long as the outputs contract remains intact.
