param tags object = {}
param enableTelemetry bool = true
param logAnalyticsWorkspaceResourceId string

param subnetForApp string = 'subnetForApp'
param subnetForDb string = 'subnetForDb'
param vnetName string
param vnetrg string

param dbServerUsername string = 'wpadmin'
@secure()
param dbServerPassword string
param dbSkuName string = 'Standard_D2ds_v4'
param dbSkuTier string = 'GeneralPurpose'

param namingConvention string = '{workloadName}-{env}-{rtype}-{loc}-{seq}'
param workloadName string = 'wpmain'
param sequence int = 1
param env string = 'prod'

param deploymentTime string = utcNow()

param zoneRedundantAppServicePlan bool = true
param appSkuCapacity int = 3
param appSkuName string = 'P1v3'

param containerRegistryUri string = 'mcr.microsoft.com'
param containerImage string = 'appsvc/wordpress-debian-php'
param containerImageVersion string = '8.3'

param wordPressCustomDomain string = ''

var diagnosticSettings = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  name: 'customDiagnosticSetting'
}

var databaseName = '${workloadName}${env}${sequence}_database'

module serverfarmModule 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'serverfarmDeployment-${deploymentTime}'
  params: {
    // Required parameters
    name: planNameModule.outputs.validName
    tags: tags
    enableTelemetry: enableTelemetry

    // Non-required parameters
    diagnosticSettings: [
      diagnosticSettings
    ]
    kind: 'linux'
    skuCapacity: appSkuCapacity
    skuName: appSkuName
    zoneRedundant: zoneRedundantAppServicePlan
  }
}

module siteModule 'br/public:avm/res/web/site:0.16.0' = {
  name: 'siteDeployment-${deploymentTime}'
  params: {
    kind: 'app'
    name: siteNameModule.outputs.validName
    serverFarmResourceId: serverfarmModule.outputs.resourceId
    tags: tags
    enableTelemetry: enableTelemetry

    basicPublishingCredentialsPolicies: [
      {
        allow: false
        name: 'ftp'
      }
      {
        allow: false
        name: 'scm'
      }
    ]
    diagnosticSettings: [
      diagnosticSettings
    ]
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    scmSiteAlsoStopped: true

    siteConfig: {
      linuxFxVersion: 'DOCKER|${containerRegistryUri}/${containerImage}:${containerImageVersion}'
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      //healthCheckPath: '/healthz'
      // metadata: [
      //   {
      //     name: 'CURRENT_STACK'
      //     value: 'dotnetcore'
      //   }
      // ]
      minTlsVersion: '1.2'
    }

    configs: [
      {
        name: 'appsettings'
        properties: {
          DOCKER_REGISTRY_SERVER_URL: 'https://mcr.microsoft.com'
          WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'true'
          DATABASE_HOST: flexibleServerModule.outputs.fqdn
          DATABASE_NAME: databaseName
          WEBSITES_CONTAINER_START_TIME_LIMIT: '1800'
          WORDPRESS_LOCALE_CODE: 'en_US'
          WORDPRESS_MULTISITE_TYPE: 'subdirectory'
          WORDPRESS_MULTISITE_CONVERT: 'true'
          CUSTOM_DOMAIN: wordPressCustomDomain
          SETUP_PHPMYADMIN: 'true'
          WORDPRESS_LOCAL_STORAGE_CACHE_ENABLED: 'false'
          ENTRA_CLIENT_ID: userAssignedIdentityModule.outputs.clientId
          ENABLE_MYSQL_MANAGED_IDENTITY: 'true'
          DATABASE_USERNAME: userAssignedIdentityModule.outputs.name

          AFD_ENABLED: 'false' // TODO: enable AFD
          // AFD_ENDPOINT: 'wpmainprod-681ba522f8-e4b8d2gcamayahe2.z01.azurefd.net' // TODO: Reference AFD endpoint

          BLOB_STORAGE_ENABLED: 'false' // TODO: Enable blob storage
          // STORAGE_ACCOUNT_NAME: storageAccountName
          // BLOB_CONTAINER_NAME: blobContainerName
          // BLOB_STORAGE_URL: '${storageAccountName}.blob.core.windows.net'
          // STORAGE_ACCOUNT_KEY: listKeys(storageAccountId, '2019-04-01').keys[0].value

          // TODO: Enable email settings
          // WP_EMAIL_CONNECTION_STRING: 'endpoint=https://${reference_variables_acsAccountId_hostName.hostName};senderaddress=${variables_acsSenderEmailAddress}@${reference_variables_ecsAccountId_mailFromSenderDomain.mailFromSenderDomain}'
          // ENABLE_EMAIL_MANAGED_IDENTITY: 'true'
        }
      }
      {
        name: 'connectionstrings'
        properties: {
          WORDPRESS_ADMIN_EMAIL: { type: 'Custom', value: '' }
          WORDPRESS_ADMIN_USER: { type: 'Custom', value: 'admin' }
          WORDPRESS_ADMIN_PASSWORD: { type: 'Custom', value: '' }
        }
      }
    ]

    vnetContentShareEnabled: true
    vnetImagePullEnabled: true
    vnetRouteAllEnabled: true

    virtualNetworkSubnetId: appSubnet.id

    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentityModule.outputs.resourceId
      ]
    }
  }
}

module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'userAssignedIdentityDeployment-${deploymentTime}'
  params: {
    // Required parameters
    name: userAssignedIdentityNameModule.outputs.validName
    tags: tags
    enableTelemetry: enableTelemetry

    // Non-required parameters
    lock: {
      kind: 'CanNotDelete'
      name: '${userAssignedIdentityNameModule.outputs.validName}-lock'
    }
  }
}

module flexibleServerModule './modules/flexibleServer.bicep' = {
  name: 'flexibleServerParentDeployment-${deploymentTime}'
  params: {
    flexibleServerName: flexibleServerNameModule.outputs.validName
    dbSkuName: dbSkuName
    dbSkuTier: dbSkuTier
    tags: tags
    enableTelemetry: enableTelemetry
    dbServerUsername: dbServerUsername
    dbServerPassword: dbServerPassword
    administratorUami: {
      identityResourceId: userAssignedIdentityModule.outputs.resourceId
      login: userAssignedIdentityModule.outputs.name
      sid: userAssignedIdentityModule.outputs.principalId
    }
    databaseName: databaseName
    dbSubnetId: dbSubnet.id
    privateDnsZoneResourceId: privateDnsZoneModule.outputs.resourceId

    diagnosticSettings: [
      diagnosticSettings
    ]
    deploymentTime: deploymentTime
  }
}

module privateDnsZoneModule 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'privateDnsZoneDeployment-${deploymentTime}'
  params: {
    name: 'privatelink.mysql.database.azure.com'
    location: 'global'
    tags: tags
    enableTelemetry: enableTelemetry

    virtualNetworkLinks: [
      {
        name: 'vnetLink'
        virtualNetworkResourceId: virtualNetwork.id
        registrationEnabled: false
      }
    ]

    lock: {
      kind: 'CanNotDelete'
      name: 'dnszone-lock'
    }
  }
}

output siteUrl string = 'https://${siteModule.outputs.defaultHostname}'

/*******************************************************************************
EXISTING RESOURCES
********************************************************************************/

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetrg)
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: subnetForApp
  parent: virtualNetwork
}

resource dbSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: subnetForDb
  parent: virtualNetwork
}

/*******************************************************************************
NAME GENERATION MODULES
********************************************************************************/

module siteNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'siteNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'app'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}

module planNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'planNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'plan'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}

module flexibleServerNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'flexibleServerNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'mysql'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}

module userAssignedIdentityNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'userAssignedIdentityNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'uami'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}
