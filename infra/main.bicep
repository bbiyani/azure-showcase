
param location string = resourceGroup().location
param baseName string = 'contosoretail'
param sbSku string = 'Standard'

var kvName = '${baseName}kv'
var saName = toLower('${baseName}sa${uniqueString(resourceGroup().id)}')
var egName = '${baseName}-eg'
var ehNsName = '${baseName}-ehns'
var ehName = 'retail-telemetry'
var sbNsName = '${baseName}-sbns'
var sbQueueName = 'order-processing'
var sbTopicName = 'order-events'
var highValueSubName = 'high-value'
var appInsightsName = '${baseName}-appi'
var planName = '${baseName}-plan'
var funcEventsName = '${baseName}-func-events'
var funcProcessName = '${baseName}-func-process'
var storageCheckpointsContainer = 'eh-checkpoints'

resource kv 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: kvName
  location: location
  properties: {
    sku: { family: 'A'; name: 'standard' }
    tenantId: subscription().tenantId
    enableSoftDelete: true
    enabledForTemplateDeployment: true
    accessPolicies: []
    enableRbacAuthorization: true
  }
}

resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: saName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: '${sa.name}/default'
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${sa.name}/default/${storageCheckpointsContainer}'
  properties: { publicAccess: 'None' }
}

resource egTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: egName
  location: location
  sku: { name: 'Basic' }
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
    publicNetworkAccess: 'Enabled'
  }
}

resource ehNs 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: ehNsName
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  name: '${ehNs.name}/${ehName}'
  properties: {
    messageRetentionInDays: 3
    partitionCount: 4
  }
}

resource ehAuthSend 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2021-11-01' = {
  name: '${ehNs.name}/${ehName}/send'
  properties: { rights: [ 'Send' ] }
}

resource ehAuthListen 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2021-11-01' = {
  name: '${ehNs.name}/${ehName}/listen'
  properties: { rights: [ 'Listen' ] }
}

resource sbNs 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: sbNsName
  location: location
  sku: { name: sbSku, tier: sbSku }
}

resource sbQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: '${sbNs.name}/${sbQueueName}'
  properties: {
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enablePartitioning: false
    enableBatchedOperations: true
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    requiresSession: true
  }
}

resource sbTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  name: '${sbNs.name}/${sbTopicName}'
  properties: {
    enableBatchedOperations: true
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    supportOrdering: true
  }
}

resource sbSub 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  name: '${sbNs.name}/${sbTopicName}/${highValueSubName}'
  properties: {
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
  }
}

resource sbRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: '${sbNs.name}/${sbTopicName}/${highValueSubName}/HighAmountFilter'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: 'Amount >= 1000'
      compatibilityLevel: 20
      requiresPreprocessing: false
    }
    action: {
      // optional: add or transform props
    }
  }
  dependsOn: [ sbSub ]
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: { Application_Type: 'web' }
}

resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  sku: { name: 'Y1'; tier: 'Dynamic' }
}

resource funcEvents 'Microsoft.Web/sites@2022-09-01' = {
  name: funcEventsName
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      appSettings: [
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY'; value: appi.properties.InstrumentationKey }
        { name: 'EVENTGRID_TOPIC_ENDPOINT'; value: egTopic.properties.endpoint }
        { name: 'ORDER_QUEUE'; value: sbQueueName }
        { name: 'ORDER_TOPIC'; value: sbTopicName }
      ]
      functionsRuntimeScaleMonitoringEnabled: true
      http20Enabled: true
    }
    httpsOnly: true
  }
}

resource funcProcess 'Microsoft.Web/sites@2022-09-01' = {
  name: funcProcessName
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      appSettings: [
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY'; value: appi.properties.InstrumentationKey }
        { name: 'ORDER_QUEUE'; value: sbQueueName }
        { name: 'ORDER_TOPIC'; value: sbTopicName }
      ]
      functionsRuntimeScaleMonitoringEnabled: true
      http20Enabled: true
    }
    httpsOnly: true
  }
}

// Outputs
output kvId string = kv.id
output egEndpoint string = egTopic.properties.endpoint
output eventHubConnListen string = listKeys(ehAuthListen.id, '2021-11-01').primaryConnectionString
output eventHubConnSend string = listKeys(ehAuthSend.id, '2021-11-01').primaryConnectionString
output serviceBusConn string = listKeys(resourceId('Microsoft.ServiceBus/namespaces/AuthorizationRules', sbNsName, 'RootManageSharedAccessKey'), '2021-11-01').primaryConnectionString
output storageConn string = 'DefaultEndpointsProtocol=https;AccountName=${sa.name};AccountKey=${listKeys(sa.id, '2023-01-01').keys[0].value};EndpointSuffix=core.windows.net'
output funcEventsName string = funcEvents.name
output funcProcessName string = funcProcess.name
output eventHubFqns string = '${ehNs.name}.servicebus.windows.net'
output serviceBusFqns string = '${sbNs.name}.servicebus.windows.net'
output queueName string = sbQueueName
output topicName string = sbTopicName
output highValueSub string = highValueSubName
output checkpointContainer string = storageCheckpointsContainer
