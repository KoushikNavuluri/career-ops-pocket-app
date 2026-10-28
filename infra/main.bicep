// Career Ops: Azure infrastructure for one environment (dev / prod).
// Phase 1 (deployApi=false): identity, logs, registry, Key Vault, storage, PostgreSQL, Azure OpenAI
//                            GPT-5 mini, Container Apps environment and role assignments.
// Phase 2 (deployApi=true):  the API container app, once an image exists in the registry.
targetScope = 'resourceGroup'

@description('Lowercase letters and digits only. Used in every resource name.')
@minLength(3)
@maxLength(12)
param appName string = 'careerops'

@allowed(['dev', 'prod'])
param environmentName string = 'dev'

@description('Region for everything except Azure OpenAI.')
param location string = resourceGroup().location

@description('Region for the Azure OpenAI resource. gpt-5-mini Global Standard is available in eastus2 and swedencentral.')
param openAiLocation string = 'eastus2'

@description('gpt-5-mini Global Standard capacity, in thousands of tokens per minute.')
@minValue(1)
param gptCapacity int = 50

param postgresAdminLogin string = 'careeropsadmin'

@secure()
@minLength(16)
param postgresAdminPassword string

@description('Entra External ID OpenID configuration URL.')
param authDiscoveryUrl string = ''

@description('Application (client) ID of the "Career Ops API" app registration.')
param authAudience string = ''

@description('Optional: app registration that can delete customer identities through Microsoft Graph.')
param graphTenantId string = ''
param graphClientId string = ''
@secure()
param graphClientSecret string = ''

param deployApi bool = false
param apiImage string = ''
param minReplicas int = 0

var suffix = uniqueString(resourceGroup().id)
var base = '${appName}-${environmentName}'
var tags = {
  app: appName
  env: environmentName
}
var hasGraph = !empty(graphTenantId) && !empty(graphClientId) && !empty(graphClientSecret)

var roleIds = {
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  blobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  openAiUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${base}-api'
  location: location
  tags: tags
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${base}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${base}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: take('acr${appName}${environmentName}${suffix}', 50)
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('kv-${appName}-${environmentName}-${suffix}', 24)
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('st${appName}${environmentName}${suffix}', 24)
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource userFiles 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'user-files'
  properties: {
    publicAccess: 'None'
  }
}

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'psql-${base}-${take(suffix, 6)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage: {
      storageSizeGB: 32
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

// pgvector + trigram must be allow-listed before CREATE EXTENSION.
resource pgExtensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'azure.extensions'
  properties: {
    value: 'VECTOR,PG_TRGM'
    source: 'user-override'
  }
}

resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'careerops'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
  dependsOn: [pgExtensions]
}

// 0.0.0.0 = "allow Azure services" (Container Apps egress). TLS is enforced by the server.
resource pgAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
  dependsOn: [pgDatabase]
}

resource dbUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'database-url'
  properties: {
    value: 'postgres://${postgresAdminLogin}:${uriComponent(postgresAdminPassword)}@${pg.properties.fullyQualifiedDomainName}:5432/careerops'
  }
}

resource graphSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (hasGraph) {
  parent: kv
  name: 'graph-client-secret'
  properties: {
    value: graphClientSecret
  }
}

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'oai-${base}-${take(suffix, 6)}'
  location: openAiLocation
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: 'oai-${base}-${take(suffix, 6)}'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource gpt5mini 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'gpt-5-mini'
  sku: {
    name: 'GlobalStandard'
    capacity: gptCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, roleIds.acrPull)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.acrPull)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, identity.id, roleIds.keyVaultSecretsUser)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsUser)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource blobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, identity.id, roleIds.blobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.blobDataContributor)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource openAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai.id, identity.id, roleIds.openAiUser)
  scope: openai
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.openAiUser)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${base}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

var baseSecrets = [
  {
    name: 'database-url'
    keyVaultUrl: dbUrlSecret.properties.secretUri
    identity: identity.id
  }
]
var graphSecrets = hasGraph
  ? [
      {
        name: 'graph-client-secret'
        keyVaultUrl: '${kv.properties.vaultUri}secrets/graph-client-secret'
        identity: identity.id
      }
    ]
  : []

var baseEnv = [
  { name: 'NODE_ENV', value: 'production' }
  { name: 'PORT', value: '8080' }
  { name: 'RUN_MIGRATIONS', value: 'true' }
  { name: 'DATABASE_URL', secretRef: 'database-url' }
  { name: 'DATABASE_SSL', value: 'true' }
  { name: 'AUTH_DISCOVERY_URL', value: authDiscoveryUrl }
  { name: 'AUTH_AUDIENCE', value: authAudience }
  { name: 'AUTH_REQUIRED_SCOPE', value: 'access_as_user' }
  { name: 'AI_PROVIDER', value: 'azure' }
  { name: 'AZURE_OPENAI_ENDPOINT', value: openai.properties.endpoint }
  { name: 'AZURE_OPENAI_DEPLOYMENT', value: gpt5mini.name }
  { name: 'AZURE_OPENAI_API_VERSION', value: '2025-04-01-preview' }
  { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
  { name: 'BLOB_ACCOUNT_URL', value: storage.properties.primaryEndpoints.blob }
]
var graphEnv = hasGraph
  ? [
      { name: 'GRAPH_TENANT_ID', value: graphTenantId }
      { name: 'GRAPH_CLIENT_ID', value: graphClientId }
      { name: 'GRAPH_CLIENT_SECRET', secretRef: 'graph-client-secret' }
    ]
  : []

resource api 'Microsoft.App/containerApps@2024-03-01' = if (deployApi) {
  name: 'ca-${base}-api'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: identity.id
        }
      ]
      secrets: concat(baseSecrets, graphSecrets)
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(baseEnv, graphEnv)
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/healthz', port: 8080 }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: { path: '/readyz', port: 8080 }
              initialDelaySeconds: 5
              periodSeconds: 15
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: 3
        rules: [
          {
            name: 'http'
            http: { metadata: { concurrentRequests: '50' } }
          }
        ]
      }
    }
  }
  dependsOn: [acrPull, kvSecretsUser, openAiUser, graphSecret]
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = kv.name
output postgresHost string = pg.properties.fullyQualifiedDomainName
output openAiEndpoint string = openai.properties.endpoint
output apiUrl string = deployApi ? 'https://${api!.properties.configuration.ingress.fqdn}' : ''
