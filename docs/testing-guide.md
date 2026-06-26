# Testing Guide

All test scripts are read/secret-scoped against an already-deployed environment.
They retrieve subscription keys at runtime via `listSecrets` (never stored).

Run order (recommended): smoke → entitlement → isolation → failover → quota → load.

## 1. Smoke tests (functional)

Sends a minimal request through every model-family API and asserts HTTP 200 +
presence of the `x-tokens-consumed` header (proves the token policy ran).

```powershell
./07-post-deploy-smoke-tests.ps1 -ResourceGroup <rg> -ApimName <apim> `
  -ParametersFile ../bicep/parameters/dev.parameters.json
# or, equivalently:
../tests/smoke-tests.ps1 -ResourceGroup <rg> -ApimName <apim> -ParametersFile ../bicep/parameters/dev.parameters.json
```

Manual variant: open `tests/smoke-tests.http` in VS Code (REST Client extension),
fill `@gateway` / `@apiKey`, and send each request — including the streaming and
negative (401) cases.

## 2. Product entitlement validation

Asserts every product `p1..pN` is linked to **all** model-family APIs.

```powershell
../tests/product-entitlement-validation.ps1 -ResourceGroup <rg> -ApimName <apim> `
  -ParametersFile ../bicep/parameters/dev.parameters.json
# Use -SampleProducts 5 to check only the first few (faster at full scale).
```

## 3. Subscription isolation validation

Drives traffic on key A and asserts key B's remaining-quota is unaffected,
proving per-key counters (keyed on `context.Subscription.Id`).

```powershell
../tests/subscription-isolation-validation.ps1 -ResourceGroup <rg> -ApimName <apim>
```

## 4. Failover validation

Static checks (automated): each pool has multiple priority tiers and each backend
has a circuit breaker. Plus a guided manual procedure for a live failover test.

```powershell
../tests/failover-validation.ps1 -ResourceGroup <rg> -ApimName <apim> `
  -ParametersFile ../bicep/parameters/dev.parameters.json
```

> Live failover cannot be forced deterministically from the client because circuit
> breaker state is per-gateway-instance and approximate
> (Microsoft Learn: *Backends in API Management*). Follow the printed manual steps
> (disable the priority-1 region's deployment, sustain traffic, observe 200s served
> by the next region).

## 5. Quota validation

Cheap mode: proves `x-tokens-remaining-quota` decreases across calls.
`-DriveToLimit`: actually drives a key to HTTP 403 (consumes real tokens — costly).

```powershell
../tests/quota-validation.ps1 -ResourceGroup <rg> -ApimName <apim>
# Aggressive (costly): add -DriveToLimit -MaxDriveIterations 2000
```

## 6. Load test (behavioural)

Concurrent small requests on one key; reports counts of 200 / 429 / 403 and the
last remaining-quota header. Not a replacement for Azure Load Testing.

```powershell
./08-load-test.ps1 -ResourceGroup <rg> -ApimName <apim> `
  -ParametersFile ../bicep/parameters/dev.parameters.json -Iterations 50 -Concurrency 5
```

## Test execution order (summary)

1. `07-post-deploy-smoke-tests.ps1` (or `tests/smoke-tests.ps1` / `smoke-tests.http`)
2. `tests/product-entitlement-validation.ps1`
3. `tests/subscription-isolation-validation.ps1`
4. `tests/failover-validation.ps1`
5. `tests/quota-validation.ps1`
6. `scripts/08-load-test.ps1`

## Interpreting results

- **200 + `x-tokens-consumed`** present → policy pipeline healthy.
- **429** → burst guardrail (25K TPM) or Foundry throttling.
- **403** → lifetime-style token quota exhausted for that key.
- **503** → all priority members unavailable (breakers tripped).
- **401** → missing/invalid subscription key (expected negative test).
