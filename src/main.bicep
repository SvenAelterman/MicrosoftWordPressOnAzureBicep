param tags object = {}
param enableTelemetry bool = true
param logAnalyticsWorkspaceResourceId string

param subnetForApp string = 'subnetForApp'
param subnetForDb string = 'subnetForDb'
param subnetForPrivateEndpoints string = 'subnetForPrivateEndpoints'
param vnetName string
param vnetrg string

param dbServerUsername string = 'wpadmin'
@secure()
param dbServerPassword string
param dbSkuName string = 'Standard_D2ds_v4'
param dbSkuTier string = 'GeneralPurpose'

param namingConvention string = '{workloadName}-{env}-{rtype}-{loc}-{seq}'
param workloadName string = 'wordpress'
param sequence int = 1
param env string = 'prod'

param deploymentTime string = utcNow()

param storageSkuName string = 'Standard_ZRS'

param zoneRedundantAppServicePlan bool = true
param appSkuCapacity int = 3
param appSkuName string = 'P1v3'

param containerRegistryUri string = 'mcr.microsoft.com'
param containerImage string = 'appsvc/wordpress-debian-php'
param containerImageVersion string = '8.3'

param wordPressCustomDomain string = ''
param wordPressAdminUser string = 'admin'
param wordPressAdminEmail string
@secure()
param wordPressAdminPassword string

param createLocks bool = true

var diagnosticSettings = {
  workspaceResourceId: logAnalyticsWorkspaceResourceId
  name: 'customDiagnosticSetting'
}

var storageAccountName = storageAccountNameModule.outputs.validName
var databaseName = '${blobContainerName}_database'
var blobContainerName = '${workloadName}${env}${sequence}2'

var storageAccountKey1SecretName = 'storageAccountKey1'
var wordPressAdminPasswordSecretName = 'wpAdminPassword'

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
    //kind: 'app'
    kind: 'app,linux,container'
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

    keyVaultAccessIdentityResourceId: userAssignedIdentityModule.outputs.resourceId

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
        // App Service settings reference: https://github.com/Azure/wordpress-linux-appservice/blob/main/WordPress/wordpress_application_settings.md
        name: 'appsettings'
        properties: {
          DOCKER_REGISTRY_SERVER_URL: 'https://${containerRegistryUri}'
          WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'true'
          DATABASE_HOST: flexibleServerModule.outputs.fqdn
          DATABASE_NAME: databaseName
          WEBSITES_CONTAINER_START_TIME_LIMIT: '1800'
          WORDPRESS_LOCALE_CODE: 'en_US'
          WORDPRESS_MULTISITE_TYPE: 'subdirectory'
          WORDPRESS_MULTISITE_CONVERT: 'true'
          //WORDPRESS_TITLE: 'Testing setting a title'
          CUSTOM_DOMAIN: wordPressCustomDomain
          SETUP_PHPMYADMIN: 'true'
          WORDPRESS_LOCAL_STORAGE_CACHE_ENABLED: 'false'
          ENTRA_CLIENT_ID: userAssignedIdentityModule.outputs.clientId
          ENABLE_MYSQL_MANAGED_IDENTITY: 'true'
          DATABASE_USERNAME: userAssignedIdentityModule.outputs.name

          AFD_ENABLED: 'false' // TODO: enable AFD
          // AFD_ENDPOINT: 'wpmainprod-681ba522f8-e4b8d2gcamayahe2.z01.azurefd.net' // TODO: Reference AFD endpoint

          BLOB_STORAGE_ENABLED: 'false'
          STORAGE_ACCOUNT_NAME: storageAccountName
          BLOB_CONTAINER_NAME: blobContainerName
          BLOB_STORAGE_URL: '${storageAccountName}.blob.${az.environment().suffixes.storage}'
          // Differs from Azure Marketplace template, which doesn't use Key Vault
          STORAGE_ACCOUNT_KEY: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=${storageAccountKey1SecretName})'

          // TODO: Enable email settings
          // WP_EMAIL_CONNECTION_STRING: 'endpoint=https://${reference_variables_acsAccountId_hostName.hostName};senderaddress=${variables_acsSenderEmailAddress}@${reference_variables_ecsAccountId_mailFromSenderDomain.mailFromSenderDomain}'
          // ENABLE_EMAIL_MANAGED_IDENTITY: 'true'
        }
      }
      {
        name: 'connectionstrings'
        properties: {
          WORDPRESS_ADMIN_EMAIL: { type: 'Custom', value: wordPressAdminEmail }
          WORDPRESS_ADMIN_USER: { type: 'Custom', value: wordPressAdminUser }
          WORDPRESS_ADMIN_PASSWORD: {
            type: 'Custom'
            value: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=${wordPressAdminPasswordSecretName})'
          }
        }
      }
    ]

    vnetContentShareEnabled: true
    vnetImagePullEnabled: true // Image is pulled from a public registry, so this is not strictly necessary
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
    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '${userAssignedIdentityNameModule.outputs.validName}-lock'
        }
      : {}
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
    privateDnsZoneResourceId: mysqlPrivateDnsZoneModule.outputs.resourceId

    diagnosticSettings: [
      diagnosticSettings
    ]
    deploymentTime: deploymentTime

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '${flexibleServerNameModule.outputs.validName}-lock'
        }
      : {}
  }
}

module mysqlPrivateDnsZoneModule 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'mysqlPrivateDnsZoneDeployment-${deploymentTime}'
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

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: 'mysql-dns-zone-lock'
        }
      : {}
  }
}

module kvPrivateDnsZoneModule 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'kvPrivateDnsZoneDeployment-${deploymentTime}'
  params: {
    name: 'privatelink.vaultcore.azure.net'
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

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: 'kv-dns-zone-lock'
        }
      : {}
  }
}

module blobPrivateDnsZoneModule 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'storagePrivateDnsZoneDeployment-${deploymentTime}'
  params: {
    name: 'privatelink.blob.${az.environment().suffixes.storage}'
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

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: 'blob-dns-zone-lock'
        }
      : {}
  }
}

module storageAccountModule 'br/public:avm/res/storage/storage-account:0.25.0' = {
  name: 'storageAccountDeployment-${deploymentTime}'
  params: {
    // Required parameters
    name: storageAccountNameModule.outputs.validName
    tags: tags
    enableTelemetry: enableTelemetry

    // Non-required parameters
    skuName: storageSkuName
    kind: 'StorageV2'
    accessTier: 'Hot'
    enableHierarchicalNamespace: false
    // Required for the App Service to access the storage account
    // (as configured here)
    allowSharedKeyAccess: true

    secretsExportConfiguration: {
      accessKey1Name: storageAccountKey1SecretName
      keyVaultResourceId: keyVaultModule.outputs.resourceId
    }

    // TODO: Private endpoint for the storage account
    publicNetworkAccess: 'Enabled'
    // Enhancement over the Azure Marketplace template, which doesn't use private endpoints
    // privateEndpoints: [
    //   {
    //     privateDnsZoneGroup: {
    //       privateDnsZoneGroupConfigs: [
    //         {
    //           privateDnsZoneResourceId: blobPrivateDnsZoneModule.outputs.resourceId
    //         }
    //       ]
    //     }
    //     service: 'blob'
    //     subnetResourceId: peSubnet.id
    //     tags: tags
    //   }
    // ]

    blobServices: {
      default: {
        containers: [
          {
            name: blobContainerName
          }
        ]
      }
    }

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '${storageAccountNameModule.outputs.validName}-lock'
        }
      : {}
  }
}

module keyVaultModule 'br/public:avm/res/key-vault/vault:0.13.0' = {
  name: 'keyVaultDeployment-${deploymentTime}'
  params: {
    // Required parameters
    name: keyVaultNameModule.outputs.validName
    tags: tags
    enableTelemetry: enableTelemetry

    // Non-required parameters
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90

    // TODO: Private endpoint for the Key Vault
    publicNetworkAccess: 'Enabled'
    // privateEndpoints: [
    //   {
    //     privateDnsZoneGroup: {
    //       privateDnsZoneGroupConfigs: [
    //         {
    //           privateDnsZoneResourceId: kvPrivateDnsZoneModule.outputs.resourceId
    //         }
    //       ]
    //     }
    //     service: 'vault'
    //     subnetResourceId: peSubnet.id
    //     tags: tags
    //   }
    // ]

    secrets: [
      {
        name: wordPressAdminPasswordSecretName
        value: wordPressAdminPassword
        contentType: 'WordPress Admin Password'
      }
    ]

    diagnosticSettings: [diagnosticSettings]

    // Add RBAC for App Service UAMI
    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
      {
        principalId: deployer().objectId
        principalType: 'User'
        roleDefinitionIdOrName: 'Key Vault Administrator'
      }
    ]

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '${keyVaultNameModule.outputs.validName}-lock'
        }
      : {}
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

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: subnetForPrivateEndpoints
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

module storageAccountNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'storageAccountNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'st'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}

module keyVaultNameModule './modules/createValidAzResourceName.bicep' = {
  name: 'keyVaultNameDeployment-${deploymentTime}'
  params: {
    workloadName: workloadName
    environment: env
    resourceType: 'kv'
    location: resourceGroup().location
    sequence: sequence
    namingConvention: namingConvention
    alwaysUseShortLocation: true
  }
}
