param flexibleServerName string
param dbSkuName string
param dbSkuTier string
param tags object
param enableTelemetry bool
param dbServerUsername string
@secure()
param dbServerPassword string
param administratorUami object
param databaseName string
param dbSubnetId string
param privateDnsZoneResourceId string
param diagnosticSettings array
param deploymentTime string

module flexibleServerModule 'br/public:avm/res/db-for-my-sql/flexible-server:0.8.0' = {
  name: 'flexibleServerDeployment-${deploymentTime}'
  params: {
    availabilityZone: -1
    name: flexibleServerName
    skuName: dbSkuName
    tier: dbSkuTier
    tags: tags
    enableTelemetry: enableTelemetry

    // Entra ID auth only will be enabled
    administratorLogin: dbServerUsername
    administratorLoginPassword: dbServerPassword
    administrators: [
      administratorUami
    ]

    backupRetentionDays: 10

    // Create the WordPress database
    databases: [
      {
        name: databaseName
        // These are required settings for WordPress so should not be parametrized
        charset: 'utf8'
        collation: 'utf8_general_ci'
      }
    ]

    // Use Private Access (virtual network integration)
    delegatedSubnetResourceId: dbSubnetId
    privateDnsZoneResourceId: privateDnsZoneResourceId

    highAvailability: 'ZoneRedundant'

    managedIdentities: {
      userAssignedResourceIds: [
        administratorUami.identityResourceId
      ]
    }

    storageAutoGrow: 'Enabled'
    storageAutoIoScaling: 'Enabled'
    storageIOPS: 400
    storageSizeGB: 64

    lock: {
      kind: 'CanNotDelete'
      name: '${flexibleServerName}-lock'
    }

    diagnosticSettings: diagnosticSettings
  }
}

// We could avoid referencing this existing resource by using string concatenation for the `configurations` resource below,
// however, using the parent property is what's recommended.
resource flexibleServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' existing = {
  name: flexibleServerName
  dependsOn: [
    flexibleServerModule
  ]
}

resource serverName_aad_auth_only 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  name: 'aad_auth_only'
  parent: flexibleServer
  properties: {
    value: 'ON'
  }
}

output fqdn string = flexibleServerModule.outputs.fqdn
