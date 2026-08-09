#!/usr/bin/env bash
# Aetherion AirOps - one-shot environment provisioning wrapper (bash).
# Thin shim that runs the PowerShell wrapper via pwsh so attendees on
# macOS/Linux can also run a single command. No arguments required.
#
#   ./provision-environment.sh                       # uses defaults
#   ./provision-environment.sh [resource-group] [location]
set -euo pipefail

RG="${1:-rg-aetherion-microhack}"
LOCATION="${2:-swedencentral}"

# --- Banner -------------------------------------------------------------------
CYAN=$'\033[36m'; DCYAN=$'\033[36;2m'; WHITE=$'\033[97m'; GRAY=$'\033[90m'; RESET=$'\033[0m'
cat <<EOF
${CYAN}
    █████╗  ██╗ ██████╗   ██████╗  ██████╗  ███████╗
   ██╔══██╗ ██║ ██╔══██╗ ██╔═══██╗ ██╔══██╗ ██╔════╝
   ███████║ ██║ ██████╔╝ ██║   ██║ ██████╔╝ ███████╗
   ██╔══██║ ██║ ██╔══██╗ ██║   ██║ ██╔═══╝  ╚════██║
   ██║  ██║ ██║ ██║  ██║ ╚██████╔╝ ██║      ███████║
   ╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝      ╚══════╝
${RESET}
${WHITE}        ✈  A E T H E R I O N   A I R O P S  ✈${RESET}

${DCYAN}   ╔══════════════════════════════════════════════════════════╗
   ║  AZURE SRE AGENT MICROHACK  ·  OPERATION CLEAR SKIES      ║
   ║                                                          ║
   ║  Mission   : Keep a Tier-0 aviation platform flying      ║
   ║  Stack     : AKS · APIM · PostgreSQL · Redis · Grafana   ║
   ║  Agent     : Reader → Contributor → Autonomous           ║
   ║  Status    : PROVISIONING FLIGHT DECK...                 ║
   ╚══════════════════════════════════════════════════════════╝${RESET}

${GRAY}   🛫 Spinning up runways ......... AKS cluster
   📡 Raising control tower ....... API Management
   🗄  Fueling data systems ........ PostgreSQL + Redis
   📊 Lighting the dashboards ..... Grafana + Monitor
   🧠 Prepping the SRE Agent ...... Knowledge base ready${RESET}

EOF

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell (pwsh) is required. Install it: https://aka.ms/powershell"
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
pwsh -NoProfile -File "$DIR/provision-environment.ps1" -ResourceGroup "$RG" -Location "$LOCATION" -NoBanner
