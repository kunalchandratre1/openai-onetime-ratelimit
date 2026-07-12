# APIM + Azure AI Foundry and lifetime token policy

A production-oriented, parameterised IaC repository that fronts multi-region Azure
AI Foundry / Azure OpenAI model deployments with **Azure API Management (Basic v2)**,
providing product-based entitlement isolation and per-subscription-key token-quota
isolation.

> **Execution note:** Nothing in this repo has been deployed for you. These are
> templates and scripts for **you** to review and run against **your** Azure
> subscription. All values marked `REPLACE-...` must be confirmed first.

## What this builds

- **APIM Basic v2** instance with system-assigned managed identity.
- **Multi-region Foundry** (Azure OpenAI) accounts + model deployments across
  Sweden Central, East US 2, West US 3 (capacities fully parameterised).
- **One APIM API per model family** (not per team/subscription):
  `foundry-gpt5-nano-api`, `foundry-gpt5-mini-api`, `foundry-gpt52-api`,
  `foundry-gpt54-api`, `foundry-embeddings-api`.
- **Backend entities per regional endpoint** + **priority backend pools** per
  model family, with **circuit-breaker failover**.
- **Products** (`p1..pN`) as entitlement boundaries, each linked to all model APIs.
- **Subscriptions** (`p{i}subscriptionteam{j}`) as per-key quota boundaries.
- **Global token policy** scoped to `foundry-*` APIs: lifetime-style token quota
  (2.05M per key) + 25K TPM burst guardrail + telemetry headers.
- **App Insights + Log Analytics** observability.

## Repository layout

```
/bicep        Infrastructure as Code (main + modules + parameters)
/policies     APIM policy XML (global + per-API)
/scripts      Deployment / operations PowerShell (+ deploy.sh)
/tests        Validation scripts and .http smoke tests
/docs         This documentation set
```

## Quickstart (dev scale: 10 products x 5 subs)

```powershell
cd scripts
./00-prereqs.ps1
./01-login-and-select-subscription.ps1 -SubscriptionId <your-sub-guid>
./02-register-providers.ps1
# 1) Confirm model versions + capacities in ../bicep/parameters/dev.parameters.json
./03-validate-quota.ps1 -ParametersFile ../bicep/parameters/dev.parameters.json
./04-deploy-infra.ps1 -ResourceGroup rg-apim-foundry-dev -Location swedencentral `
    -ParametersFile ../bicep/parameters/dev.parameters.json -WhatIfOnly   # preview
./04-deploy-infra.ps1 -ResourceGroup rg-apim-foundry-dev -Location swedencentral `
    -ParametersFile ../bicep/parameters/dev.parameters.json               # deploy
./07-post-deploy-smoke-tests.ps1 -ResourceGroup rg-apim-foundry-dev -ApimName apim-foundry-dev-001 `
    -ParametersFile ../bicep/parameters/dev.parameters.json
```

For full scale (80 products x 10 subs = 800 keys) use `prod.parameters.json`.

## Before you deploy — required confirmations

1. **Model versions** (`modelVersion: REPLACE-...`) for each family in the chosen
   parameters file — confirm against the Foundry model availability docs.
2. **Per-region/model capacities** fit your approved Foundry quota
   (see [docs/known-limitations.md](known-limitations.md) and run `03-validate-quota.ps1`).
3. **Globally-unique names** (`apimName`, `foundryAccounts[].name`).
4. Read [docs/known-limitations.md](known-limitations.md) — especially the
   **lifetime token quota** gap (APIM has no true "lifetime" period; Yearly is used).

## Documentation index

| Doc | Purpose |
| --- | --- |
| [architecture.md](architecture.md) | Design, topology, request flow, diagram |
| [deployment-guide.md](deployment-guide.md) | Step-by-step deploy + what-if |
| [operations-runbook.md](operations-runbook.md) | Day-2 ops, scaling, monitoring |
| [testing-guide.md](testing-guide.md) | How to run every validation/test |
| [rollback-guide.md](rollback-guide.md) | Reversal procedures |
| [assumptions.md](assumptions.md) | Assumptions needing your confirmation |
| [known-limitations.md](known-limitations.md) | Supported-feature caveats & gaps |

## Source of truth

All resource schemas and policy semantics are taken from official Microsoft Learn
documentation. Key references are cited inline in each file and collected in
[architecture.md](architecture.md).
