[CmdletBinding(SupportsShouldProcess = $true)]
param ()

[string]$ResourceGroupName = "wordpress-test-rg-cnc-01"

$DeploymentResults = New-AzResourceGroupDeployment `
    -Name "WordPressDeployment" `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile "./src/main.bicep" `
    -TemplateParameterFile "./src/sven.bicepparam"

if ($DeploymentResults.ProvisioningState -eq 'Succeeded') {
    $DeploymentResults.Outputs | Format-Table -Property Key, @{Name = 'Value'; Expression = { $_.Value.Value } }
    
    Write-Host "🔥 Deployment successful!"
}
else {
    $DeploymentResults
}
    