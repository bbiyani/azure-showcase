#!/usr/bin/env bash
set -euo pipefail

RG=${RG:-rg-contoso-retail}
LOC=${1:-westeurope}
BASE=${2:-contosoretail}

echo ">> Creating resource group $RG in $LOC"
az group create -n "$RG" -l "$LOC" >/dev/null

echo ">> Deploying Bicep..."
az deployment group create -g "$RG" -f infra/main.bicep -p baseName="$BASE" -o json > /tmp/contoso-deploy.json

echo ">> Extracting outputs..."
jq -r '.properties.outputs | with_entries(.value |= .value)' /tmp/contoso-deploy.json > /tmp/contoso-outputs.json
cat /tmp/contoso-outputs.json

KVID=$(jq -r .kvId /tmp/contoso-outputs.json)
KVNAME=$(az resource show --ids "$KVID" --query name -o tsv)
FUNC_EVENTS=$(jq -r .funcEventsName /tmp/contoso-outputs.json)
FUNC_PROCESS=$(jq -r .funcProcessName /tmp/contoso-outputs.json)

echo ">> Granting Key Vault Secrets User to Function identities"
for APP in "$FUNC_EVENTS" "$FUNC_PROCESS"; do
  PRINCIPAL_ID=$(az webapp identity show -g "$RG" -n "$APP" --query principalId -o tsv)
  az role assignment create --assignee-principal-type ServicePrincipal --assignee "$PRINCIPAL_ID" --scope "$KVID" --role "Key Vault Secrets User" >/dev/null
done

echo ">> Storing connection strings into Key Vault"
SB_CONN=$(jq -r .serviceBusConn /tmp/contoso-outputs.json)
EH_SEND=$(jq -r .eventHubConnSend /tmp/contoso-outputs.json)
EH_LISTEN=$(jq -r .eventHubConnListen /tmp/contoso-outputs.json)
STG_CONN=$(jq -r .storageConn /tmp/contoso-outputs.json)

az keyvault secret set --vault-name "$KVNAME" -n ServiceBusConnection --value "$SB_CONN" >/dev/null
az keyvault secret set --vault-name "$KVNAME" -n EventHubsConnectionSend --value "$EH_SEND" >/dev/null
az keyvault secret set --vault-name "$KVNAME" -n EventHubsConnectionListen --value "$EH_LISTEN" >/dev/null
az keyvault secret set --vault-name "$KVNAME" -n StorageConnection --value "$STG_CONN" >/dev/null

SB_SEC_URI=$(az keyvault secret show --vault-name "$KVNAME" -n ServiceBusConnection --query id -o tsv)
EH_SEND_URI=$(az keyvault secret show --vault-name "$KVNAME" -n EventHubsConnectionSend --query id -o tsv)
EH_LISTEN_URI=$(az keyvault secret show --vault-name "$KVNAME" -n EventHubsConnectionListen --query id -o tsv)
STG_URI=$(az keyvault secret show --vault-name "$KVNAME" -n StorageConnection --query id -o tsv)

echo ">> Setting Key Vault references on Function Apps"
EG_ENDPOINT=$(jq -r .egEndpoint /tmp/contoso-outputs.json)

az webapp config appsettings set -g "$RG" -n "$FUNC_EVENTS" --settings   AzureWebJobsStorage="@Microsoft.KeyVault(SecretUri=$STG_URI)"   AzureWebJobsServiceBus="@Microsoft.KeyVault(SecretUri=$SB_SEC_URI)"   AzureWebJobsEventHub="@Microsoft.KeyVault(SecretUri=$EH_LISTEN_URI)"   EVENTGRID_TOPIC_ENDPOINT="$EG_ENDPOINT" >/dev/null

az webapp config appsettings set -g "$RG" -n "$FUNC_PROCESS" --settings   AzureWebJobsStorage="@Microsoft.KeyVault(SecretUri=$STG_URI)"   AzureWebJobsServiceBus="@Microsoft.KeyVault(SecretUri=$SB_SEC_URI)"   AzureWebJobsEventHub="@Microsoft.KeyVault(SecretUri=$EH_LISTEN_URI)" >/dev/null

echo ">> Done. Outputs stored at /tmp/contoso-outputs.json"
