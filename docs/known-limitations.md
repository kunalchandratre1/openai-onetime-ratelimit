# Known Limitations & Operator Notes

Validated against official Microsoft Learn documentation. Where the requested
behaviour is not natively supported, the safest supported design is used and the
gap is described here.

## 1. No true "lifetime" token quota (most important)

**Requirement:** independent **lifetime** quota cap of 2.05M tokens per key.

**What APIM supports:** the `llm-token-limit` policy provides `token-quota` with
`token-quota-period` ∈ `{Hourly, Daily, Weekly, Monthly, Yearly}`. **There is no
"Lifetime"/never-resetting option.** (Ref: *Limit large language model API token
usage*.)

**Design used:** `token-quota=2050000` with `token-quota-period=Yearly` keyed on
`context.Subscription.Id`. This caps each key at 2.05M tokens per **yearly** window
rather than once-forever.

**Supported alternatives if you need a hard, non-resetting cap:**
- Treat the Yearly window as effectively lifetime for a time-boxed hackathon
  (simplest; default).
- Add an out-of-band ledger: emit token metrics (`llm-emit-token-metric` /
  App Insights) and have an external job **disable/suspend** a subscription once its
  cumulative tokens reach 2.05M. This is the only way to guarantee a true lifetime
  cap with current features.
- `quota-by-key` supports `renewal-period="0"` (infinite/lifetime) **but only counts
  calls or bandwidth, not tokens** (Ref: *Set usage quota by key*), so it cannot
  enforce a token cap directly. It can serve as a coarse lifetime **call** backstop.

## 2. Streaming token accounting is approximate

For streaming requests (`stream:true`), the platform **estimates** prompt tokens
(always) and completion tokens; exact per-token charging cannot be guaranteed in
policy alone (Ref: *Considerations for token counts and estimation*).

**Mitigation in this repo:** the per-API policy forces
`stream_options.include_usage=true` so the backend returns a final usage object
where supported. Non-streaming calls use **actual** usage
(`estimate-prompt-tokens="false"`). Residual gap: concurrent/near-concurrent
requests can momentarily exceed the limit before counters settle.

## 3. Token counters are per-gateway, not instance-aggregated

`llm-token-limit` tracks usage **independently at each gateway** and does not
aggregate across the whole instance or across regional/workspace gateways
(Ref: policy *Usage notes*). On Basic v2 (single managed gateway) this is not a
practical issue, but be aware if you later add workspace gateways. The v2 tiers also
use a **token-bucket** algorithm (vs sliding window in classic) — keep
`tokens-per-minute` consistent if you ever configure the policy at multiple scopes
with the same `counter-key`.

## 4. Backend pools + circuit breaker need a PREVIEW API version

Backend **pools** (`properties.type='Pool'`) and the backend **circuitBreaker**
property are surfaced via a **preview** API version of
`Microsoft.ApiManagement/service/backends`. This repo pins
`2024-06-01-preview` in `apim-backends.bicep`. The **feature is documented and
supported** on Basic v2 (only the **Consumption** tier excludes the circuit breaker;
Ref: *Backends in API Management*). Only one circuit-breaker **rule** per backend is
supported. If your governance forbids preview API versions, use the supported
fallback: a single backend per API via `set-backend-service base-url` plus a retry
policy, sacrificing automatic priority failover.

## 5. APIM Basic v2 capability boundaries

Confirmed available on Basic v2: policies (incl. `llm-token-limit`, `quota-by-key`,
`set-backend-service`, `authentication-managed-identity`), products, subscriptions,
backends, pools, circuit breakers, App Insights logging, scale to 10 units.

**Not available on Basic v2** (Ref: *v2 tiers overview* / *feature comparison*):
multi-region APIM deployment, availability zones, VNet injection, self-hosted
gateway, backup/restore, Event Grid events, direct Management API access. None are
required by this design — **multi-region applies to Foundry, not APIM**.

> **Operator confirmation item:** verify the **maximum products and subscriptions**
> for Basic v2 against the current *API Management limits* table before relying on
> 80 products / 800 subscriptions. The design imposes no architectural blocker, but
> service limits can change and should be checked for your tenant. If a hard cap is
> hit, split across multiple APIM instances or raise a support request.

## 6. Foundry quota is regional / per-subscription / per-model

TPM & RPM are defined **per region, per subscription, per model/deployment-type**
(Ref: *Azure OpenAI quotas and limits — Regional quota allocation*). Spreading
deployments across Sweden Central / East US 2 / West US 3 increases usable
throughput per subscription. `capacities` must fit your **approved** quota in each
region; `03-validate-quota.ps1` helps verify before deploying. Default max **30**
Azure OpenAI resources per region per subscription, **32** standard deployments per
resource — both comfortably above this topology.

## 7. Managed-identity authorization

APIM's system-assigned identity must hold **Cognitive Services User** on each
Foundry account; the template creates these role assignments, which requires the
deploying principal to have permission to assign roles. Role assignment propagation
can take a short time after deployment before the first calls succeed.

## 8. Cost & test realism

Driving a key to its 2.05M cap (`quota-validation.ps1 -DriveToLimit`,
`08-load-test.ps1` at high iterations) consumes real tokens and incurs cost. Default
test modes prove the mechanism cheaply (counter decrements, header presence) without
exhausting quotas.

## 9. Names & soft-delete

`apimName` and `foundryAccounts[].name` must be globally unique. A deleted APIM may
linger in **soft-deleted** state; purge before reusing the same name.
