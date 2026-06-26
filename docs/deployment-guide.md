# Deployment Guide

All commands run from the `scripts/` folder unless noted. Primary path is
PowerShell 7+; a `deploy.sh` Bash equivalent covers the core deploy flow.

## 0. Prerequisites

- Azure CLI (with Bicep) and PowerShell 7+.
- An Azure subscription where you can create APIM, Cognitive Services (OpenAI),
  and role assignments (you need **Owner** or **User Access Administrator** on the
  resource group to create the RBAC role assignment).
- Approved **Foundry quota** for each model/region/deployment-type you intend to
  deploy (see `known-limitations.md`).

```powershell
./00-prereqs.ps1
```

## 1. Login & select subscription

```powershell
./01-login-and-select-subscription.ps1 -SubscriptionId <your-sub-guid>
```

## 2. Register resource providers (idempotent)

```powershell
./02-register-providers.ps1
```

Registers: `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`,
`Microsoft.Insights`, `Microsoft.OperationalInsights`, `Microsoft.Authorization`.

## 3. Confirm parameters

Edit the parameters file for your environment:

- `bicep/parameters/dev.parameters.json` — 10 products x 5 subs (cheap validation)
- `bicep/parameters/prod.parameters.json` — 80 products x 10 subs (full scale)
- `bicep/parameters/example.parameters.json` — annotated baseline reference

Must-confirm fields:

- `modelTopology[].modelVersion` — replace every `REPLACE-WITH-CONFIRMED-VERSION`.
- `capacities` — TPM units per region/model (1 unit = 1,000 TPM).
- `apimName`, `foundryAccounts[].name` — globally unique.
- `apimPublisherEmail`, `apimPublisherName`.

## 4. Pre-flight quota check (read-only)

```powershell
./03-validate-quota.ps1 -ParametersFile ../bicep/parameters/dev.parameters.json
```

Review requested vs available capacity per region. Request increases at
<https://aka.ms/oai/stuquotarequest> if short.

## 5. What-if (preview, no changes)

```powershell
./04-deploy-infra.ps1 `
  -ResourceGroup rg-apim-foundry-dev `
  -Location swedencentral `
  -ParametersFile ../bicep/parameters/dev.parameters.json `
  -WhatIfOnly
```

## 6. Deploy

```powershell
./04-deploy-infra.ps1 `
  -ResourceGroup rg-apim-foundry-dev `
  -Location swedencentral `
  -ParametersFile ../bicep/parameters/dev.parameters.json
```

The single `main.bicep` deployment provisions everything in order:
App Insights/Log Analytics → APIM → Foundry accounts + deployments → RBAC →
backends/pools → APIs → products → subscriptions → global policy.

> APIM Basic v2 instance creation typically takes a while (tens of minutes).
> Foundry model deployments are serialized per account (`@batchSize(1)`).

## 7. (Optional) Re-apply policies only

When iterating on policy XML without a full redeploy:

```powershell
./05-apply-apim-artifacts.ps1 `
  -ResourceGroup rg-apim-foundry-dev `
  -ApimName apim-foundry-dev-001 `
  -ParametersFile ../bicep/parameters/dev.parameters.json
```

## 8. (Optional) Scale products/subscriptions without full redeploy

Change `productCount` / `subscriptionsPerProduct` in the params file, then:

```powershell
./06-create-products-and-subscriptions.ps1 `
  -ResourceGroup rg-apim-foundry-dev `
  -ApimName apim-foundry-dev-001 `
  -ParametersFile ../bicep/parameters/dev.parameters.json
```

## 9. Validate

See [testing-guide.md](testing-guide.md). Minimum:

```powershell
./07-post-deploy-smoke-tests.ps1 -ResourceGroup rg-apim-foundry-dev `
  -ApimName apim-foundry-dev-001 -ParametersFile ../bicep/parameters/dev.parameters.json
```

## Bash alternative (core flow)

```bash
cd scripts
./deploy.sh <subId> rg-apim-foundry-dev swedencentral ../bicep/parameters/dev.parameters.json --what-if-only
./deploy.sh <subId> rg-apim-foundry-dev swedencentral ../bicep/parameters/dev.parameters.json
```

## Deployment order (summary)

1. `00-prereqs.ps1`
2. `01-login-and-select-subscription.ps1`
3. `02-register-providers.ps1`
4. `03-validate-quota.ps1`
5. `04-deploy-infra.ps1 -WhatIfOnly`
6. `04-deploy-infra.ps1`
7. `05-apply-apim-artifacts.ps1` *(only when changing policies separately)*
8. `06-create-products-and-subscriptions.ps1` *(only when rescaling separately)*
9. Tests (see testing guide)
