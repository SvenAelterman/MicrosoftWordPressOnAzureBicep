param afdProfileName string
param endpointName string

param customDomainName string

param workloadName string
param sequence int
param environment string

param blobStorageUri string
param appServiceUri string

param blobContainerName string

var sequenceFormatted = format('{0:00}', sequence)
var resourceName = '${workloadName}-${environment}-${sequenceFormatted}-{type}'

var useCustomDomain = !empty(customDomainName)

resource afdProfile 'Microsoft.Cdn/profiles@2025-06-01' existing = {
  name: afdProfileName
}

resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2025-06-01' existing = {
  name: endpointName
  parent: afdProfile
}

/*******************************************************************************
ORIGIN GROUPS AND ORIGINS (BLOB AND APP SERVICE)
********************************************************************************/

resource blobOriginGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  name: replace(resourceName, '{type}', 'origin-group-blob')
  parent: afdProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    trafficRestorationTimeToHealedOrNewEndpointsInMinutes: null
    sessionAffinityState: 'Enabled'
  }
}

resource blobOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  name: replace(resourceName, '{type}', 'origin-blob')
  parent: blobOriginGroup
  properties: {
    hostName: blobStorageUri
    httpPort: 80
    httpsPort: 443
    originHostHeader: blobStorageUri
    priority: 1
    weight: 1000
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: null
    enabledState: 'Enabled'
  }
}

resource appOriginGroup 'Microsoft.Cdn/profiles/originGroups@2025-06-01' = {
  name: replace(resourceName, '{type}', 'origin-group-app')
  parent: afdProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    trafficRestorationTimeToHealedOrNewEndpointsInMinutes: null
    sessionAffinityState: 'Enabled'
  }
  dependsOn: [
    afdProfile
  ]
}

resource afdProfileName_afdAppOriginGroupName_afdAppOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2025-06-01' = {
  name: replace(resourceName, '{type}', 'origin-app')
  parent: appOriginGroup
  properties: {
    hostName: appServiceUri
    httpPort: 80
    httpsPort: 443
    originHostHeader: appServiceUri
    priority: 1
    weight: 1000
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: null
    enabledState: 'Enabled'
  }
}

/*******************************************************************************
RULES
********************************************************************************/

resource afdRuleSet 'Microsoft.Cdn/profiles/ruleSets@2025-06-01' = {
  name: replace(replace(resourceName, '{type}', 'rule-set'), '-', '')
  parent: afdProfile
}

resource afdRule_blobRouting 'Microsoft.Cdn/profiles/ruleSets/rules@2025-06-01' = {
  name: replace(replace(resourceName, '{type}', 'rule'), '-', '')
  parent: afdRuleSet
  properties: {
    order: 1
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
          operator: 'BeginsWith'
          negateCondition: false
          matchValues: [
            '${blobContainerName}/wp-content/uploads/'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
          originGroupOverride: {
            forwardingProtocol: 'MatchRequest'
            originGroup: {
              id: blobOriginGroup.id
            }
          }
          cacheConfiguration: {
            isCompressionEnabled: 'Enabled'
            queryStringCachingBehavior: 'UseQueryString'
            cacheBehavior: 'OverrideAlways'
            cacheDuration: '3.00:00:00'
          }
        }
      }
    ]
    matchProcessingBehavior: 'Stop'
  }
  dependsOn: [
    // Explicit dependency required because the origin must exist,
    // but the implicit dependency is only on the origin group
    blobOrigin
  ]
}

resource afdRule_cacheStaticFiles 'Microsoft.Cdn/profiles/ruleSets/rules@2025-06-01' = {
  name: replace(replace(resourceName, '{type}', 'rule-cache-static-files'), '-', '')
  parent: afdRuleSet
  properties: {
    order: 2
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
          operator: 'BeginsWith'
          negateCondition: false
          matchValues: [
            'wp-includes/'
            'wp-content/themes/'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
      {
        name: 'UrlFileExtension'
        parameters: {
          typeName: 'DeliveryRuleUrlFileExtensionMatchConditionParameters'
          operator: 'Equal'
          negateCondition: false
          matchValues: [
            'css'
            'js'
            'gif'
            'png'
            'jpg'
            'ico'
            'ttf'
            'otf'
            'woff'
            'woff2'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
          cacheConfiguration: {
            isCompressionEnabled: 'Enabled'
            queryStringCachingBehavior: 'UseQueryString'
            cacheBehavior: 'OverrideAlways'
            cacheDuration: '3.00:00:00'
          }
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Access-Control-Allow-Origin'
          value: appServiceUri
        }
      }
    ]
    matchProcessingBehavior: 'Stop'
  }
}

resource afdCustomDomain 'Microsoft.Cdn/profiles/customDomains@2025-06-01' = if (useCustomDomain) {
  name: replace(resourceName, '{type}', 'custom-domain')
  parent: afdProfile
  properties: {
    hostName: customDomainName
    tlsSettings: {
      certificateType: 'ManagedCertificate'
    }
  }
}

/*******************************************************************************
ROUTE
********************************************************************************/

resource afdDefaultRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2025-06-01' = {
  name: replace(resourceName, '{type}', 'route-default')
  parent: afdEndpoint
  properties: {
    customDomains: useCustomDomain
      ? [
          { id: afdCustomDomain.id }
        ]
      : []
    originGroup: {
      id: appOriginGroup.id
    }
    originPath: null
    ruleSets: [
      {
        id: afdRuleSet.id
      }
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'MatchRequest'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

/*******************************************************************************
OUTPUTS
********************************************************************************/

output afdEndpointUri string = afdEndpoint.properties.hostName
