param(
 [string]$Location = "westeurope",
 [string]$Base = "contosoretail",
 [string]$ResourceGroup = "rg-contoso-retail"
)

Write-Host ">> Creating resource group $ResourceGroup in $Location"
az group create -n $ResourceGroup -l $Location | Out-Null

Write-Host ">> Deploying Bicep..."
# Ensure az returns JSON; capture output and handle errors
$deployJson = az deployment group create -g $ResourceGroup -f infra/main.bicep -p baseName=$Base -o json --only-show-errors

if (-not $deployJson) {
 Write-Host "ERROR: Deployment did not return JSON. Ensure 'az' is installed and logged in."
 exit1
}

try {
 $deploy = $deployJson | ConvertFrom-Json -ErrorAction Stop
} catch {
 Write-Host "ERROR: Failed to parse deployment JSON:\n$deployJson"
 exit1
}

# Fix: Create proper hashtable and save to scripts folder
$outputsHash = @{}
if ($deploy -and $deploy.properties -and $deploy.properties.outputs) {
 foreach ($p in $deploy.properties.outputs.PSObject.Properties) {
 $name = $p.Name
 if ($name) {
 try { $val = $p.Value.value } catch { $val = $null }
 $outputsHash[$name] = $val
 }
 }
} else {
 Write-Host "ERROR: Deployment returned no outputs."
 exit1
}

$outs = $outputsHash | ConvertTo-Json -Depth10

# Save to scripts folder instead of /tmp/
$outputPath = Join-Path $PSScriptRoot 'contoso-outputs.json'
Set-Content -Path $outputPath -Value $outs

Write-Host ">> Outputs saved to: $outputPath"

$KVID = (Get-Content $outputPath | ConvertFrom-Json).kvId
$KVNAME = az resource show --ids $KVID --query name -o tsv
$FUNC_EVENTS = (Get-Content $outputPath | ConvertFrom-Json).funcEventsName
$FUNC_PROCESS = (Get-Content $outputPath | ConvertFrom-Json).funcProcessName

Write-Host ">> Granting Key Vault Secrets User to Function identities"
$apps = @($FUNC_EVENTS, $FUNC_PROCESS)
foreach ($app in $apps) {
 $principal = az webapp identity show -g $ResourceGroup -n $app --query principalId -o tsv
 az role assignment create --assignee-principal-type ServicePrincipal --assignee $principal --scope $KVID --role "Key Vault Secrets User" | Out-Null
}

Write-Host ">> Storing secrets"
$outsObj = Get-Content $outputPath | ConvertFrom-Json
$SB = $outsObj.serviceBusConn
$EH_SEND = $outsObj.eventHubConnSend
$EH_LISTEN = $outsObj.eventHubConnListen
$STG = $outsObj.storageConn

az keyvault secret set --vault-name $KVNAME -n ServiceBusConnection --value $SB | Out-Null
az keyvault secret set --vault-name $KVNAME -n EventHubsConnectionSend --value $EH_SEND | Out-Null
az keyvault secret set --vault-name $KVNAME -n EventHubsConnectionListen --value $EH_LISTEN | Out-Null
az keyvault secret set --vault-name $KVNAME -n StorageConnection --value $STG | Out-Null

$SB_URI = az keyvault secret show --vault-name $KVNAME -n ServiceBusConnection --query id -o tsv
$EH_SEND_URI = az keyvault secret show --vault-name $KVNAME -n EventHubsConnectionSend --query id -o tsv
$EH_LISTEN_URI = az keyvault secret show --vault-name $KVNAME -n EventHubsConnectionListen --query id -o tsv
$STG_URI = az keyvault secret show --vault-name $KVNAME -n StorageConnection --query id -o tsv

$EG_ENDPOINT = $outsObj.egEndpoint

Write-Host ">> Setting app settings (Key Vault references)"
az webapp config appsettings set -g $ResourceGroup -n $FUNC_EVENTS --settings `
 AzureWebJobsStorage=@("`@Microsoft.KeyVault(SecretUri=$STG_URI)") `
 AzureWebJobsServiceBus=@("`@Microsoft.KeyVault(SecretUri=$SB_URI)") `
 AzureWebJobsEventHub=@("`@Microsoft.KeyVault(SecretUri=$EH_LISTEN_URI)") `
 EVENTGRID_TOPIC_ENDPOINT=$EG_ENDPOINT | Out-Null

az webapp config appsettings set -g $ResourceGroup -n $FUNC_PROCESS --settings `
 AzureWebJobsStorage=@("`@Microsoft.KeyVault(SecretUri=$STG_URI)") `
 AzureWebJobsServiceBus=@("`@Microsoft.KeyVault(SecretUri=$SB_URI)") `
 AzureWebJobsEventHub=@("`@Microsoft.KeyVault(SecretUri=$EH_LISTEN_URI)") | Out-Null

Write-Host ">> Done. Outputs at $outputPath"
