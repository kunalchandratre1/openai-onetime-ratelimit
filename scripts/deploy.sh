#!/usr/bin/env bash
# =============================================================================
# deploy.sh  -  Bash equivalent of the core deploy flow (login -> providers ->
#               what-if -> deploy). For full lifecycle (tests, rollback) use the
#               numbered PowerShell scripts which are the primary, supported path.
#
# Usage:
#   ./deploy.sh <subscriptionId> <resourceGroup> <location> <parametersFile> [--what-if-only]
# Example:
#   ./deploy.sh 00000000-0000-0000-0000-000000000000 rg-apim-foundry-dev swedencentral \
#       ../bicep/parameters/dev.parameters.json
# =============================================================================
set -euo pipefail

SUBSCRIPTION_ID="${1:?subscriptionId required}"
RESOURCE_GROUP="${2:?resourceGroup required}"
LOCATION="${3:?location required}"
PARAMETERS_FILE="${4:?parametersFile required}"
WHATIF_ONLY="${5:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../bicep/main.bicep"
DEPLOYMENT_NAME="apim-foundry-$(date +%Y%m%d%H%M%S)"

echo "[INFO ] Selecting subscription ${SUBSCRIPTION_ID}..."
az account set --subscription "${SUBSCRIPTION_ID}"

echo "[INFO ] Registering resource providers..."
for p in Microsoft.ApiManagement Microsoft.CognitiveServices Microsoft.Insights Microsoft.OperationalInsights Microsoft.Authorization; do
  az provider register -n "$p" 1>/dev/null
done

echo "[INFO ] Ensuring resource group ${RESOURCE_GROUP}..."
az group create -n "${RESOURCE_GROUP}" -l "${LOCATION}" 1>/dev/null

echo "[INFO ] Building Bicep..."
az bicep build --file "${TEMPLATE_FILE}" 1>/dev/null

echo "[INFO ] Running what-if..."
az deployment group what-if \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAMETERS_FILE}"

if [[ "${WHATIF_ONLY}" == "--what-if-only" ]]; then
  echo "[WARN ] --what-if-only set; stopping before deployment."
  exit 0
fi

echo "[INFO ] Deploying ${DEPLOYMENT_NAME}..."
az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAMETERS_FILE}"

echo "[ OK  ] Deployment complete."
az deployment group show -g "${RESOURCE_GROUP}" -n "${DEPLOYMENT_NAME}" --query properties.outputs
