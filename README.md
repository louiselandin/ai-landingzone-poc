# AI Landing Zone — Bicep demo-template

En pedagogisk Bicep-template som skapar grundinfrastrukturen för en AI-applikation på Azure. Detta är "steg 1" — själva applikationen (Container App + eventuella appspecifika resurser) deployas i "steg 2".

---

## 1. Vad templaten gör

Skapar en resursgrupp och fyller den med generiska, återanvändbara resurser som de flesta AI-applikationer behöver:

| Resurs | Roll |
|---|---|
| Log Analytics workspace | Centralt loggnav — alla resurser skickar diagnostik hit |
| Application Insights | Telemetri för applikationen och för Foundry-traces |
| Storage Account + `invoices`-container | Lagring för dokument, bilder, embeddings-källor |
| Key Vault (RBAC-läge) | Hemligheter (API-nycklar till externa tjänster m.m.) |
| Azure AI Foundry-konto (AIServices) | Multi-modell inferens-endpoint |
| Foundry-projekt (`proj-{workloadName}`) | Arbetsyta för agenter, evals, connections |
| 3 modelldeployments | `gpt-4o-mini`, `o4-mini`, `text-embedding-3-small` (för `gpt-4o`, se TODO i `modules/foundry.bicep`) |
| Application Insights-koppling på projektet | Strömmar Foundry-telemetri till AppI |
| Container Registry (Basic) | Image registry för Container Appen i steg 2 |
| Container Apps Environment | Värd-miljö för Container Appen i steg 2 |
| User-assigned Managed Identity | Identitet som Container Appen binder och autentiserar med |
| Role assignments | Ger managed identity:n exakt rätt åtkomst (least privilege) |

## 2. Vad templaten **inte** gör

- **Ingen Container App** — det är steg 2.
- **Inget VNet, inga subnets, inga private endpoints, inget Bastion, ingen NAT Gateway.** Allt körs publikt med Entra-autentisering.
- **Inga custom content filters** — Foundrys default-filter `Microsoft.DefaultV2` används automatiskt.
- **Inga workload-specifika resurser** — t.ex. SQL Server, Cosmos DB eller AI Search lämnas till steg 2 om de behövs.
- **Ingen App Configuration.**
- **Ingen produktionshärdning** — purge protection är av på Key Vault, network ACLs är "Allow all", Basic ACR-SKU, etc.

## 3. Förutsättningar

- Azure CLI installerat (`az --version`).
- Bicep CLI installerat (`az bicep install` eller `az bicep upgrade`).
- Inloggad: `az login` och rätt subscription vald: `az account set --subscription <id>`.
- Den inloggade användaren har `Owner` på subscription-nivån (enklast) **eller** `Contributor` + `User Access Administrator`. Sistnämnda krävs för att skapa rolltilldelningarna i `rbac.bicep`.
- Resource provider `Microsoft.App` registrerad:
  ```bash
  az provider register --namespace Microsoft.App
  ```

### Om namnstandarden

Alla resurser namnges enligt mönstret `{prefix}-{workloadName}-{environment}` (eller `{prefix}{workloadName}{environment}` för resurser med strikta regler som Storage Account och Container Registry). Inga slumpmässiga hashar — namnen är läsbara för människor.

| Resurstyp | Mönster | Exempel (workloadName=`branslefakturor`, env=`demo`) |
|---|---|---|
| Resursgrupp | `rg-{wl}-{env}` | `rg-branslefakturor-demo` |
| Foundry-konto | `aif-{wl}-{env}` | `aif-branslefakturor-demo` |
| Foundry-projekt | `proj-{wl}` | `proj-branslefakturor` |
| Log Analytics | `log-{wl}-{env}` | `log-branslefakturor-demo` |
| Application Insights | `appi-{wl}-{env}` | `appi-branslefakturor-demo` |
| Storage Account | `st{wl}{env}` | `stbranslefakturordemo` |
| Key Vault | `kv-{wl}-{env}` | `kv-branslefakturor-demo` |
| Container Registry | `cr{wl}{env}` | `crbranslefakturordemo` |
| Container Apps Env | `cae-{wl}-{env}` | `cae-branslefakturor-demo` |
| Managed Identity | `id-{wl}-{env}` | `id-branslefakturor-demo` |

**OBS:** Storage Account, Key Vault, Container Registry och Foundrys custom subdomain måste vara **globalt unika** i Azure. Välj ett `workloadName` som är unikt nog — ta med ett team- eller tenant-marker (t.ex. `acmefuelinv` istället för bara `test`). `workloadName` är begränsat till 3–16 tecken eftersom Storage Account och Key Vault max är 24 tecken totalt.

**Tips:** `environment`-parametern accepterar `demo`, `poc`, `dev`, `test`, `prod`. **Default är `demo`** — det signalerar tydligt i resursnamnen att den här deploymenten är en läroartefakt, inte en riktig PoC på väg till produktion.

## 4. Hur man deployar

```bash
# 1) Torrkör först — visar exakt vad som kommer skapas/ändras utan att deploya:
az deployment sub what-if \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam

# 2) Skarp deploy:
az deployment sub create \
  --location swedencentral \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Ändra `workloadName` i `main.bicepparam` innan du kör.

## 5. Beskrivning per resurs

- **Log Analytics + Application Insights** — observability-stacken. Workspace-baserad AppI lagrar all data i Log Analytics så att man kan korrelera app-traces med plattforms-loggar i KQL.
- **Storage Account** — StorageV2, LRS, TLS 1.2+, ingen public blob access, **inga delade nycklar** (Entra tvingas). En blob-container `invoices` skapas.
- **Key Vault** — RBAC-läge (inga access policies), soft-delete 7 dagar, purge protection av (för PoC-städning).
- **Foundry-konto** — `Microsoft.CognitiveServices/accounts` med `kind: AIServices`. `disableLocalAuth: true` så att bara Entra fungerar. `allowProjectManagement: true` så att vi kan skapa projekt under det.
- **Modelldeployments** — tre deployments (`gpt-4o-mini`, `o4-mini`, `text-embedding-3-small`), sekventiellt med `@batchSize(1)` för att undvika race conditions. Alla har samma TPM-kapacitet via parametern `modelCapacity`. `gpt-4o` ligger utkommenterad i `modules/foundry.bicep` med instruktion om hur du begär kvothöjning.
- **Foundry-projekt** — `proj-{workloadName}`. Detta är där agenter, evals och knowledge connections lever.
- **AppInsights-connection på projektet** — gör att Foundrys agent-traces och eval-resultat hamnar i din AppI.
- **Container Registry** — Basic SKU, ingen admin user, bara Entra.
- **Container Apps Environment** — Consumption-only, inget VNet, app-loggar till Log Analytics.
- **Managed Identity** — user-assigned (UAMI). Container Appen i steg 2 binder den och får all access "gratis".
- **Role assignments** — fem roller (se tabell i uppgiftsbeskrivningen), alla med deterministiska GUID-namn så att omdeploy är idempotent.

## 6. Vad nästa steg är

Outputs från `main.bicep` är kontraktet mellan plattform och workload. Steg 2 (Container App-deployen) konsumerar dem:

- `containerAppsEnvironmentId` — appen körs här
- `managedIdentityResourceId` — appen binder denna identitet
- `containerRegistryLoginServer` — appens image pushas hit
- `foundryAccountEndpoint`, `foundryProjectName` — appen pratar med dessa
- `storageBlobEndpoint`, `invoiceContainerName` — appen läser/skriver härifrån
- `keyVaultUri` — appen läser secrets här
- `appInsightsConnectionString` — appen skickar telemetri hit

Eventuella **workload-specifika** resurser (t.ex. en SQL Server för struktured data, eller en AI Search-instans för hybrid retrieval) skapas också i steg 2 — de hör inte hemma i landing zonen eftersom de är specifika för just den här applikationen.

## 7. Hur man river ner

```bash
az group delete --name rg-<workloadName>-<env> --yes --no-wait
```

**Viktigt:** Foundry-kontot (Cognitive Services) har **soft-delete** påslaget av Azure som default — kontot finns kvar i ~48 timmar efter borttagning. Om du behöver deploya om templaten med samma namn omedelbart, purge:a kontot:

```bash
az cognitiveservices account purge \
  --location swedencentral \
  --name aif-<workloadName>-<env> \
  --resource-group rg-<workloadName>-<env>
```

(Resursgruppen måste anges även om den redan är borta — det är ett Azure-quirk.)

## 8. Vanliga problem

| Symptom | Sannolik orsak | Lösning |
|---|---|---|
| `AuthorizationFailed` vid första deployen | Användaren saknar `User Access Administrator` på subscription/RG | Be Owner att tilldela rollen, eller deploya som Owner |
| `ResourceDeploymentFailure` på en modelldeployment | Modellen är inte tillgänglig i `swedencentral`, eller versionen är fel | Kommentera ut modellen i `modules/foundry.bicep` och försök igen. Validera mot https://learn.microsoft.com/azure/ai-services/openai/concepts/models |
| `RoleAssignmentUpdateNotPermitted` | Försöker ändra principalType eller principalId på en befintlig roll | Ta bort role assignment i portalen och deploya om |
| `StorageAccountAlreadyTaken` / `VaultAlreadyExists` | Någon annan i Azure har redan tagit namnet (globalt unika resurser) | Välj ett mer unikt `workloadName` — t.ex. lägg på team-/tenant-prefix |
| Foundry-projektet skapas men appen får 401 | RBAC har inte propagerat (~5 min) | Vänta och försök igen — eller verifiera tilldelningen i portalen |
| `Microsoft.App not registered` | RP inte registrerad | `az provider register --namespace Microsoft.App` och vänta ~2 min |

## 9. Anpassa till din workload

Det som typiskt behöver ändras när du klonar templaten för en ny AI-applikation:

| Vad | Var | Hur |
|---|---|---|
| Workload-namn (syns i alla resursnamn) | [`main.bicepparam`](main.bicepparam) | Ändra `param workloadName = '...'` |
| Miljö-etikett (`demo`/`poc`/`dev`/`test`/`prod`) | [`main.bicepparam`](main.bicepparam) | Ändra `param environment = '...'` |
| Vilka modeller som deployas | [`modules/foundry.bicep`](modules/foundry.bicep) | Redigera `modelDeployments`-arrayen (name, modelName, modelVersion, skuName, capacity) |
| TPM-kapacitet per modell | [`main.bicepparam`](main.bicepparam) | Ändra `param modelCapacity = 10` |
| Blob-container-namn | [`modules/storage.bicep`](modules/storage.bicep) | Ändra default på `param containerName = 'invoices'` eller lyft upp som top-level parameter |
| Regional placering | [`main.bicepparam`](main.bicepparam) | Avkommentera och sätt `param location = '...'`. OBS: modellistan i `foundry.bicep` är validerad mot `swedencentral`. |
| Tags | [`main.bicepparam`](main.bicepparam) | Avkommentera tags-blocket |

Vill du **lägga till en helt ny resurs** (t.ex. AI Search eller Cosmos DB) — skapa en ny modul under `modules/` och anropa den från `main.bicep`. Glöm inte att lägga till motsvarande role assignment i `modules/rbac.bicep` så att appens managed identity får åtkomst.

## 10. Förväntad kostnad

Grov uppskattning för en **idle demo-deployment** (inga modellanrop, ingen apptrafik) i `swedencentral`:

| Resurs | Månadskostnad (ca, SEK) |
|---|---|
| Log Analytics (PerGB2018, ingen inkommande data) | ~0 |
| Application Insights (workspace-baserad, ingen data) | ~0 |
| Storage Account (StorageV2 LRS, tomt) | <5 |
| Key Vault (Standard, inga operations) | <5 |
| Container Registry (Basic) | ~50 |
| Container Apps Environment (Consumption, ingen app) | ~0 |
| Managed Identity | 0 |
| Foundry-konto (AIServices) | 0 i basavgift — bara per-token vid anrop |
| **Totalt idle** | **~50–70 SEK/mån** |

Tillkommer vid faktisk användning: tokens till modellerna (gpt-4o-mini ≈ 0.0015 USD / 1k input-tokens), Container App-körningstid, Log Analytics-ingestion, lagrade blobs/images. För prod-volym: kör Azure Pricing Calculator med dina förväntade siffror.

## 11. Pedagogisk not — plattform vs workload

Cloud Adoption Frameworket skiljer mellan **plattform** (det som ett centralt team äger och som flera workloads delar/använder lika) och **workload** (det som ett produkt-team äger och som är specifikt för en applikation).

Den här templaten är **plattformsdelen för en enskild AI-workload**: den är generisk nog att passa de flesta AI-appar (alla behöver Foundry, lagring, secrets, observability, en hostingmiljö och en identitet), men den är inte en hel applikation.

I praktiken skulle ett AI Platform-team:

1. Köra **den här templaten** för varje ny AI-workload (steg 1).
2. Lämna över outputs till applikations-teamet, som deployar sin Container App, sina databaser, sina connection strings i Key Vault, etc. (steg 2).

Den här uppdelningen gör att plattformsteamet kan uppgradera baseline (t.ex. byta från Basic till Premium ACR, eller lägga till private endpoints) utan att rota i någon enskild apps kod — så länge outputs-kontraktet är intakt.
