param deploymentTime string
param createLocks bool
param tags object = {}
param communicationServiceName string
param emailServiceName string
param acsEmailSenderAddress string
param acsEmailSenderDisplayName string = 'Do Not Reply'
param enableTelemetry bool
param diagnosticSettings object
param uamiPrincipalId string

module communicationServiceModule './communicationService.bicep' = {
  name: 'communicationServiceDeployment-${deploymentTime}'
  params: {
    name: communicationServiceName
    tags: tags
    enableTelemetry: enableTelemetry

    diagnosticSettings: [diagnosticSettings]

    dataLocation: 'United States'
    linkedDomains: [
      emailServiceModule.outputs.domainResourceIds[0]
    ]

    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '${communicationServiceName}-lock'
        }
      : {}
  }
}

module emailServiceModule 'br/public:avm/res/communication/email-service:0.3.3' = {
  name: 'emailServiceDeployment-${deploymentTime}'
  params: {
    name: emailServiceName
    tags: tags
    enableTelemetry: enableTelemetry

    dataLocation: 'United States'

    domains: [
      {
        domainManagement: 'AzureManaged'
        lock: createLocks
          ? {
              kind: 'CanNotDelete'
              name: 'email-domain-lock'
            }
          : {}
        name: 'AzureManagedDomain'
        senderUsernames: [
          {
            displayName: acsEmailSenderDisplayName
            name: acsEmailSenderAddress
            userName: acsEmailSenderAddress
          }
        ]
        tags: tags
        userEngagementTracking: 'Disabled'
      }
      // LATER: Add custom email domain
    ]
    lock: createLocks
      ? {
          kind: 'CanNotDelete'
          name: '-lock'
        }
      : {}
  }
}

// Create custom role for Azure Communication Services and assign to UAMI
resource customEmailContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, communicationServiceName, 'CustomEmailContributorRole')
  properties: {
    roleName: 'Custom Email Contributor Role - ${communicationServiceName}'
    description: 'Custom Email Contributor role for Azure Communication Services'
    assignableScopes: [
      resourceGroup().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Communication/CommunicationServices/Read'
          'Microsoft.Communication/CommunicationServices/Write'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

module roleAssignmentModule 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.0' = {
  name: 'roleAssignmentDeployment'
  params: {
    principalId: uamiPrincipalId
    roleDefinitionIdOrName: customEmailContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

output hostName string = communicationServiceModule.outputs.hostName
output emailServiceDomainResourceId string = emailServiceModule.outputs.domainResourceIds[0]
output emailServiceDomainName string = emailServiceModule.outputs.domainNamess[0]
output customRoleName string = customEmailContributorRole.properties.roleName
output customRoleId string = customEmailContributorRole.id
