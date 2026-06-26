# Operations Runbook (Day-2)

## Monitoring

- **Application Insights** (`appInsightsName`) receives APIM request telemetry via
  the configured logger/diagnostic. Use it for latency, failures, and dependency
  calls to Foundry backends.
- **Log Analytics** (`logAnalyticsName`) backs App Insights (workspace-based).
- Track the telemetry headers emitted by the global policy:
  - `x-tokens-consumed` — tokens used by the request (prompt + completion).
  - `x-tokens-remaining-quota` — estimated remaining tokens for the period.
  - `x-tokens-remaining-minute` — remaining TPM in the current minute window.
  - `x-retry-after` — recommended wait after a 429/403.

### Useful signals

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Client gets `403` | Token quota exhausted for that key | Expected; key has hit its lifetime-style cap. Raise `subscriptionTokenQuota` or reset period. |
| Client gets `429` | 25K TPM burst guardrail or Foundry throttling | Expected burst control; client should back off using `x-retry-after`. |
| Client gets `503` | All pool members' circuit breakers tripped | Check Foundry health/quota in all regions for that model. |
| Latency spikes | Foundry usage-tier exceeded | Spread load across regions; consider PTU. |

## Scaling

### APIM scale units
Edit `apimCapacity` (Basic v2 supports up to 10) and redeploy `04-deploy-infra.ps1`.

### Products / subscriptions
Edit `productCount` / `subscriptionsPerProduct`, then either redeploy
`04-deploy-infra.ps1` or run `06-create-products-and-subscriptions.ps1` (idempotent,
no full redeploy).

### Foundry capacity (TPM)
Edit `capacities` (units of 1,000 TPM) and redeploy. Confirm headroom first with
`03-validate-quota.ps1`. Capacity is bounded by your approved regional quota.

### Add a region or model
1. Add the account to `foundryAccounts` (new region) and/or extend `modelTopology`
   (`regions[]`, `capacities` keys, a new family entry + its policy file).
2. For a new model family, also add a per-API policy XML under `/policies` and map
   it in `bicep/main.bicep` (`apiPolicyMap`) and `05-apply-apim-artifacts.ps1`.
3. Redeploy.

## Rotating subscription keys
Use the APIM management plane (`regenerateKey`) per subscription, or the portal.
Keys are not stored in this repo.

## Quota / period changes
- `subscriptionTokenQuota` — lifetime-style token cap per key.
- `subscriptionTokenQuotaPeriod` — `Hourly|Daily|Weekly|Monthly|Yearly`
  (no true "lifetime"; see known-limitations.md).
- `subscriptionTpmGuardrail` — burst TPM per key.
Change in params, then redeploy or run `05-apply-apim-artifacts.ps1`.

## Backups / DR
- Basic v2 does **not** support APIM backup/restore or multi-region APIM. Treat the
  Bicep + parameters as the source of truth; redeploy to recover the config.
- Foundry accounts/deployments are recreated from `foundry-deployments.bicep`.

## Health checks
- `tests/failover-validation.ps1` — confirms pools + breakers are configured.
- `tests/product-entitlement-validation.ps1` — confirms entitlements intact.
- `07-post-deploy-smoke-tests.ps1` — end-to-end request through every API.
