# Rollback Guide

Rollback is performed by `scripts/09-rollback.ps1`, which supports three modes.
All deletes are idempotent (a missing object is treated as already removed).

> Foundry **accounts and model deployments** are preserved unless you explicitly
> delete the resource group. This avoids accidentally destroying expensive/quota-
> backed model deployments during a routine APIM artifact rollback.

## Mode: Policies (least invasive)

Resets the global service policy and every per-API policy to default
(`<base/>` only), disabling token quota/burst and managed-identity routing.

```powershell
./09-rollback.ps1 -ResourceGroup rg-apim-foundry-dev -ApimName apim-foundry-dev-001 `
  -ParametersFile ../bicep/parameters/dev.parameters.json -Mode Policies
```

Use when a policy change caused regressions and you want to revert governance
quickly while keeping APIs/products/subscriptions intact.

## Mode: Artifacts (default)

Resets policies, then deletes **subscriptions → products → APIs → backend pools →
backends**. Foundry, APIM instance, App Insights remain.

```powershell
./09-rollback.ps1 -ResourceGroup rg-apim-foundry-dev -ApimName apim-foundry-dev-001 `
  -ParametersFile ../bicep/parameters/dev.parameters.json -Mode Artifacts
```

## Mode: Full (optionally delete the resource group)

Same as Artifacts, and — only with both `-DeleteResourceGroup` and `-Confirm` —
deletes the entire resource group (including Foundry accounts/deployments, APIM,
and observability). **Destructive and irreversible.**

```powershell
./09-rollback.ps1 -ResourceGroup rg-apim-foundry-dev -ApimName apim-foundry-dev-001 `
  -ParametersFile ../bicep/parameters/dev.parameters.json -Mode Full `
  -DeleteResourceGroup -Confirm
```

## Rollback order (summary)

1. **Policies** — neutralise governance/routing (fast, reversible by re-applying).
2. **Subscriptions** — remove keys.
3. **Products** — remove entitlements (`deleteSubscriptions=true`).
4. **APIs** — remove the five model-family APIs.
5. **Backend pools**, then **single backends**.
6. *(Full only)* **Resource group delete** — removes Foundry + APIM + observability.

## Recovery after rollback

Re-run the deployment flow in [deployment-guide.md](deployment-guide.md)
(`04-deploy-infra.ps1`). Because the templates are idempotent, redeploying restores
the full configuration from `main.bicep` + parameters.

## Notes & caveats

- APIM **soft-delete**: a deleted Basic v2 APIM name may be retained in a
  soft-deleted state for a period; purge it before reusing the exact name, or pick
  a new `apimName`.
- Deleting a product with `deleteSubscriptions=true` removes its subscriptions even
  if the subscription-delete loop already ran (safe/idempotent).
