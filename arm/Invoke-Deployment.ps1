#Requires -Version 3.0
#Requires -Module AzureRM.Resources



# Variables
param (
    [string] $DeploymentName = "SolarEdge.ARMDevelopment",
    [string] $ResourceGroupLocation = "eastus",
    [string] $ARMTemplate = 'azuredeploy.json',
    [string] $TemplateParameters = 'azuredeploy.parameters.json',
    [Switch] $ValidateOnly
)


$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ARMTemplate = "$here\$ARMTemplate"
$TemplateParameters = "$here\$TemplateParameters"

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

# Functions
function Format-ValidationOutput {
    param ($ValidationOutput, [int] $Depth = 0)
    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}

# Select the right subscription
Select-AzureRmSubscription -SubscriptionID 3b9fbe96-f23e-4d67-8b55-20caadb3f4eb

Write-Output "Creating Resource Groups ..."

# Create the Infrastructure Resource Group
$ResourceGroupName = 'cm-solaredge'
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Force


# Define deployment parameters 
$parameters = @{
    #Name                  = "$DeploymentName-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))"
    ResourceGroupName     = $ResourceGroupName
    TemplateFile          = $ARMTemplate
    TemplateParameterFile = $TemplateParameters
    Mode                  = 'Complete'
}

If ($ValidateOnly) {
    #Throw [System.NotImplementedException]
    Test-AzureRmResourceGroupDeployment @parameters -Verbose -ErrorVariable ErrorMessages
}
else {
    Write-Output "Deploying Environment ..."

    # Deploy the ARM template
    New-AzureRmResourceGroupDeployment @parameters -Verbose -Force -ErrorVariable ErrorMessages

    if ($ErrorMessages) {
        Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
        break
    }
}

