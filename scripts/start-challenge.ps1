# =============================================================================
# Aetherion AirOps - start a challenge
# -----------------------------------------------------------------------------
# Injects the fault(s) for the given challenge (root cause stays hidden) and
# tells you how to verify your fix. Progress is gated: you can only start a
# challenge once the previous one has been completed.
#
# Usage:
#   ./scripts/start-challenge.ps1 1
#   ./scripts/start-challenge.ps1 -Number 5
# =============================================================================
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [int]$Number
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'challenge-lib.ps1')

Start-AetherionChallenge -Number $Number
