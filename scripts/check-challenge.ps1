# =============================================================================
# Aetherion AirOps - check (grade) a challenge
# -----------------------------------------------------------------------------
# Grades the given challenge against live cluster / APIM state (plus self-attest
# questions where applicable). For incident challenges the injected fault must be
# truly cleared - symptom-only or "wait it out" fixes will not pass.
#
# Usage:
#   ./scripts/check-challenge.ps1 1
#   ./scripts/check-challenge.ps1 -Number 5
# =============================================================================
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [int]$Number
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'challenge-lib.ps1')

$passed = Test-AetherionChallenge -Number $Number
if (-not $passed) { exit 1 }
exit 0
