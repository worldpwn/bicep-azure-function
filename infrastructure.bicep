param sku string = 'Y1'
param location string = resourceGroup().location
param scaleOutLimits int = 1
param stage string = 'tst'

@sys.description('api key for external service')
@secure()
param apiKey string

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: '${location}${stage}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2021-08-01' = {
  name: 'default'
  parent: storageAccount
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2021-08-01' = {
  name: 'default'
  parent: storageAccount
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: 'lw--${location}-${stage}'
  location: location
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${location}-${stage}'
  location: location
  kind: 'azurefunctionapp'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    WorkspaceResourceId: logWorkspace.id
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: 'hp-${location}-${stage}'
  location: location
  sku: {
    name: sku
  }
}

resource functionApp 'Microsoft.Web/sites@2021-01-01' = {
  location: location
  name: 'fa-${location}-${stage}'
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: false
    siteConfig: {
      functionAppScaleLimit: scaleOutLimits
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value};'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'AZURE_TABLE_STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'AZURE_TABLE_STORAGE_ACCOUNT_KEY'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'AZURE_QUEUE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'ApiKey'
          value: apiKey
        }
      ]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: 'kv-${location}-${stage}'
  location: location
  properties: {
    enableSoftDelete: true
    publicNetworkAccess: 'disabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 7
    tenantId: tenant().tenantId
    accessPolicies: [
      {
        objectId: functionApp.identity.principalId
        permissions: {
          certificates: [
            'all'
          ]
          keys: [
            'all'
          ]
          secrets: [
            'all'
          ]
          storage: [
            'all'
          ]
        }
        tenantId: tenant().tenantId
      }
    ]
  }

  resource apiKeySecret 'secrets' = {
    name: 'ExternalServiceApiKey'
    properties: {
      contentType: 'text/plain'
      value: apiKey
    }
  }
}
