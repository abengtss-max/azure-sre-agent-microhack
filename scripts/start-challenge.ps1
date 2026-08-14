#Requires -Version 7.0
# =============================================================================
# Aetherion AirOps - start a challenge
# -----------------------------------------------------------------------------
# Sets up the given challenge: for the incident challenges (2-7) it injects the
# fault(s) with the root cause hidden; for Challenge 1 it just prints the mission
# briefing (no fault - the board stays green). It then tells you how to verify
# with check-challenge.ps1. Challenges can be started in any order.
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
