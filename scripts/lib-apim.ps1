# Aetherion AirOps - set an APIM product policy via the ARM REST API.
#
# The base Azure CLI has no 'az apim product policy' command (only product
# create/list/show/update), so inject-failure.ps1 and reset-environment.ps1
# set the product policy by PUTting it directly to ARM. Returns $true on success.
function Set-AetherionApimProductPolicy {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$ApimName,
        [Parameter(Mandatory)][string]$PolicyXml,
        [string]$ProductId = 'aetherion-ops',
        [string]$SubscriptionId = ''
    )
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $SubscriptionId = (az account show --query id -o tsv 2>$null)
    }
    $body = @{ properties = @{ format = 'xml'; value = $PolicyXml } } | ConvertTo-Json -Compress
    $tmp = Join-Path $env:TEMP ("apim-policy-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".json")
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/products/$ProductId/policies/policy?api-version=2022-08-01"
    $prevEnc = $env:PYTHONIOENCODING
    # APIM returns the policy with a BOM that the Windows console can't encode; force UTF-8 to avoid a cosmetic crash.
    $env:PYTHONIOENCODING = 'utf-8'
    az rest --method put --url $url --body "@$tmp" --headers "Content-Type=application/json" --output none 2>$null | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    if ($null -eq $prevEnc) { Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $prevEnc }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $ok
}
