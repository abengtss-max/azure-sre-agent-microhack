#!/usr/bin/env bash
# Aetherion AirOps - inject a failure for a MicroHack challenge (bash version).
#
# Usage:
#   ./inject-failure.sh crew-scheduling db-pool
#   ./inject-failure.sh booking latency
#   ./inject-failure.sh flight-ops crash
#   ./inject-failure.sh apim throttle
#
# App fault modes: none | latency | error | crash | memory | db-pool
set -euo pipefail

SERVICE="${1:-}"
FAULT="${2:-}"
NS="aetherion"
ENV_FILE="$(dirname "$0")/.env.aetherion.json"

if [[ -z "$SERVICE" || -z "$FAULT" ]]; then
  echo "Usage: $0 <flight-ops|crew-scheduling|booking|baggage|telemetry-ingest|gateway|apim> <none|latency|error|crash|memory|db-pool|throttle>"
  exit 1
fi

if [[ "$SERVICE" == "apim" ]]; then
  if [[ "$FAULT" != "throttle" ]]; then echo "For 'apim', only 'throttle' is supported."; exit 1; fi
  RG=$(jq -r '.resourceGroup' "$ENV_FILE")
  APIM=$(jq -r '.apimName' "$ENV_FILE")
  TMP=$(mktemp --suffix=.xml)
  cat > "$TMP" <<'XML'
<policies>
  <inbound>
    <base />
    <rate-limit-by-key calls="5" renewal-period="60" counter-key="@(context.Subscription.Id)" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
XML
  echo "Applying restrictive rate-limit (5 calls / 60s) on APIM product 'aetherion-ops'..."
  az apim product policy create --resource-group "$RG" --service-name "$APIM" \
    --product-id aetherion-ops --policy-file "$TMP" --policy-format xml
  echo "APIM throttle injected."
  exit 0
fi

# Map the internal fault name to the opaque service profile the app actually reads
# (kept in sync with app/src/server.js): standard=none r1=latency r2=error
# r3=crash r4=memory r5=db-pool. The deployment env never names the fault.
case "$FAULT" in
  none)    PROFILE=standard ;;
  latency) PROFILE=r1 ;;
  error)   PROFILE=r2 ;;
  crash)   PROFILE=r3 ;;
  memory)  PROFILE=r4 ;;
  db-pool) PROFILE=r5 ;;
  *)       PROFILE=standard ;;
esac
echo "Setting service profile '$PROFILE' on deployment '$SERVICE'..."
kubectl set env "deploy/$SERVICE" -n "$NS" "SVC_PROFILE=$PROFILE"
kubectl rollout status "deploy/$SERVICE" -n "$NS" --timeout=120s
echo "Fault '$FAULT' injected into '$SERVICE'."
