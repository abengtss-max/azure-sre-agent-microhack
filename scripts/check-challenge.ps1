# =============================================================================
# Aetherion AirOps - check (grade) a challenge
# -----------------------------------------------------------------------------
# Validates the REAL remediation for the given challenge against live cluster /
# APIM state. On success it unlocks the next challenge. Symptom-only or
# "wait it out" fixes will not pass - the injected fault must be truly cleared.
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
