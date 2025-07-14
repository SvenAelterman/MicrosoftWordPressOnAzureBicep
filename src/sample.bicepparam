using 'main.bicep'

param tags = {
  createdDate: ''
  createdBy: ''
  AppProfile: 'WordPress'
  WordPressDeploymentId: ''
}

param enableTelemetry = true

param logAnalyticsWorkspaceResourceId = ''

param vnetName = 'sites-prod-vnet-eastus-01'
param vnetrg = 'sites-networking-prod-rg-eastus-01'

param dbServerPassword = '<TODO: Retrieve me from Key Vault>'

param wordPressAdminEmail = 'your_email@example.com'
param wordPressAdminPassword = '<TODO: Retrieve me from Key Vault>'
