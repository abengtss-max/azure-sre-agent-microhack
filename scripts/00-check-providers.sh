#!/usr/bin/env bash
# Aetherion AirOps - resource provider preflight (bash version)
# Registers every Azure resource provider the environment needs before deployment.
set -euo pipefail

SUBSCRIPTION_ID="${1:-}"
if [[ -n "$SUBSCRIPTION_ID" ]]; then
  echo "Setting subscription to $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

PROVIDERS=(
  Microsoft.ContainerService
  Microsoft.ContainerRegistry
  Microsoft.DBforPostgreSQL
  Microsoft.Cache
  Microsoft.ApiManagement
  Microsoft.OperationalInsights
  Microsoft.OperationsManagement
  Microsoft.Insights
  Microsoft.Dashboard
  Microsoft.Authorization
  Microsoft.Network
  Microsoft.Compute
  Microsoft.Storage
)

TO_REGISTER=()
echo "Checking ${#PROVIDERS[@]} resource providers..."
for p in "${PROVIDERS[@]}"; do
  state=$(az provider show --namespace "$p" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
  if [[ "$state" != "Registered" ]]; then
    echo "  [$p] = $state -> registering"
    az provider register --namespace "$p" >/dev/null
    TO_REGISTER+=("$p")
  else
    echo "  [$p] = Registered"
  fi
done

if [[ ${#TO_REGISTER[@]} -eq 0 ]]; then
  echo "All providers already registered."
  exit 0
fi

echo "Waiting for ${#TO_REGISTER[@]} provider(s) to finish registering..."
for p in "${TO_REGISTER[@]}"; do
  while true; do
    sleep 10
    state=$(az provider show --namespace "$p" --query registrationState -o tsv 2>/dev/null || echo "NotFound")
    echo "  [$p] = $state"
    [[ "$state" == "Registered" ]] && break
  done
done

echo "All required providers are registered."
