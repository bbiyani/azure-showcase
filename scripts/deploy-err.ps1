param(
  [string]$Location = "westeurope",
  [string]$Base = "contosoretail",
  [string]$ResourceGroup = "rg-contoso-retail"
)

Write-Host ">> Creating resource group $ResourceGroup in $Location"
az group create -n $ResourceGroup -l $Location | Out-Null

$log = Join-Path $env:TEMP 'az-deploy.log'
Write-Host ">> Deploying Bicep..."
$deploy = az deployment group create -g $ResourceGroup -f infra/main.bicep -p baseName=$Base -o json --only-show-errors 2> $log | ConvertFrom-Json -ErrorAction Stop
$outs = $deploy.properties.outputs.PSObject.Properties | ForEach-Object { @{ ($_.Name) = $_.Value.value } } | ConvertTo-Json
Set-Content -Path /tmp/contoso-outputs.json -Value $outs

$KVID = (Get-Content /tmp/contoso-outputs.json | ConvertFrom-Json).kvId
$KVNAME = az resource show --ids $KVID --query name -o tsv
$FUNC_EVENTS = (Get-Content /tmp/contoso-outputs.json | ConvertFrom-Json).funcEventsName
$FUNC_PROCESS = (Get-Content /tmp/contoso-outputs.json | ConvertFrom-Json).funcProcessName

Write-Host ">> Granting Key Vault Secrets User to Function identities"
$apps = @($FUNC_EVENTS, $FUNC_PROCESS)
foreach ($app in $apps) {
  $principal = az webapp identity show -g $ResourceGroup -n $app --query principalId -o tsv
  az role assignment create --assignee-principal-type ServicePrincipal --assignee $principal --scope $KVID --role "Key Vault Secrets User" | Out-Null
}

Write-Host ">> Storing secrets"
$outsObj = Get-Content /tmp/contoso-outputs.json | ConvertFrom-Json
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

Write-Host ">> Done. Outputs at /tmp/contoso-outputs.json"
