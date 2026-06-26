# Assumptions (require your confirmation)

These are decisions made to produce a runnable repository. Review and adjust
before deploying.

## Scale / counts (brief contained a discrepancy)

The brief is internally inconsistent about counts:

- **High-level objective + non-negotiables**: 80 products × 10 subscriptions =
  **800 keys**, 2.05M each → **1.64B** ceiling.
- **Section 5 + Section 11**: "p1–p10", "5 subscriptions per product", "10 products
  and 50 subscriptions".

**Resolution applied:** counts are fully parameterised (`productCount`,
`subscriptionsPerProduct`). We honour the non-negotiable 80/800 design in
`prod.parameters.json`, and also ship `dev.parameters.json` at 10×5 (=50) for the
smaller scenario. Confirm which is intended per environment.

## Entitlement model

- "p1–p10: all models" is interpreted as: **every product is linked to every model
  family API**. Products therefore differ as isolation/quota boundaries, not by
  which models they expose. Confirm if you instead want differentiated model
  entitlements per product (the topology supports it — link a subset of APIs).

## Lifetime token cap

- 2.05M is enforced via `llm-token-limit` `token-quota` with
  `token-quota-period="Yearly"` (the closest supported window). APIM has **no true
  "lifetime" period** — see `known-limitations.md`. Confirm Yearly reset is
  acceptable, or accept the documented partial alternatives.

## Models, versions, deployment types

- `modelVersion` is set to `REPLACE-WITH-CONFIRMED-VERSION` for every family. You
  **must** set real, currently-available versions (per the Foundry model docs).
- `deploymentType` defaults to `GlobalStandard`. Confirm this matches your quota
  grant and data-residency requirements (alternatives: `DataZoneStandard`,
  `Standard`).
- Model family → deployment names assumed: `gpt-5-nano`, `gpt-5-mini`, `gpt-5.2`,
  `gpt-5.4`, `text-embedding-3-large`. Confirm exact model identifiers.

## Capacities

- `capacities` values are placeholder TPM units (1 unit = 1,000 TPM). They must fit
  your **approved regional quota** per model/subscription. Run
  `03-validate-quota.ps1` and tune.

## Networking & access

- Public network access is enabled on APIM and Foundry accounts (Basic v2 does not
  support VNet injection; Standard v2/Premium v2 do). Confirm if you require private
  networking — that implies a different APIM SKU.
- Foundry local auth (API keys) is left **enabled** on accounts by default
  (`localAuthEnabled=true` in `modules/foundry-account.bicep`), but APIM uses
  managed identity only. Set it to `false` to force Entra-only auth.

## RBAC prerequisites

- The deploying principal needs rights to create **role assignments** (Owner or
  User Access Administrator on the resource group) because the template grants APIM's
  managed identity **Cognitive Services User** on each Foundry account.

## API surface

- Each API exposes one operation (chat completions, or embeddings for the
  embeddings API) matching the Azure OpenAI data-plane shape. Add operations
  (e.g. `/completions`, `/responses`) if your clients need them.
- `api-version` is a required query parameter; the default used by tests is
  `2024-10-21`. Confirm the data-plane API version your clients/models require.

## Region selection

- Control-plane `location` defaults to `swedencentral`. Confirm APIM v2 and your
  quota are available there (see *Availability of v2 tiers* docs).
