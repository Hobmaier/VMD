<#

.SYNOPSIS
    Install the VMD PowerShell module

.DESCRIPTION
    This script will install the VMD PowerShell module into users directory.

.PARAMETER AzureStorageConfigXMLPath
    Full path to your XML Path which includes custom storage accounts, e.g. c:\temp\DNS8-VMD-Config.xml

.EXAMPLE
    Install-VMDPSModule.ps1
    This will install the PowerShell module into users PowerShell directory

.EXAMPLE
    Install-VMDPSModule.ps1 -AzureStorageConfigXMLPath c:\temp\VMD-Config.xml
    This will install the PowerShell module and copies your custom VMD-Config.xml into the correct directory

#> 

param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_})]
    $AzureStorageConfigXMLPath
)
Write-host 'Installing VMD PowerShell Module'
# Global Install
# Copy-Item $PSScriptRoot\UDESetup $Env:ProgramFiles\WindowsPowerShell\Modules\ -Force -Recurse

#Install requirements to support CredentialManager
#install-packageprovider -name NuGet -MinimumVersion 2.8.5.201 -Scope "CurrentUser" -Force
#install-module -name CredentialManager -RequiredVersion 2.0 -Scope "CurrentUser" -Force

$paths = $env:PSModulePath.Split(';')
foreach ($path in $paths)
{
    #Another method: 
    #[Environment]::GetEnvironmentVariable('PSModulePath','User').split(";")
    #Fix OfficeDevPnP exclusion as it adds itself to into $env:PSModulePath
    if (($path.Indexof(('\Users\').ToLower()) -gt 0) -and ($path.Indexof('OfficeDevPnP') -lt 0) -and ($path.Indexof('SharePointPnPPowerShellOnline') -lt 0) -and ($path.Indexof('.vscode') -lt 0))
    {
         Write-Host 'Install PowerShell Module to ' $path
         If (!$path)
         {
             FixPSHomePath
             mkdir $path\VMD
         }
         If (!(Get-Item $path\VMD -ErrorAction SilentlyContinue)) { mkdir $path\VMD }
         Copy-Item $PSScriptRoot\VMD $path -Force -Recurse -ErrorAction stop
         If ($AzureStorageConfigXMLPath) {Copy-Item $AzureStorageConfigXMLPath -Destination $path\VMD\VMD-Config.xml -Force}
    }
}

Write-host 'Done' -ForegroundColor Green

start-sleep 5


Function FixPSHomePath
{

    #Save the current value in the $p variable. 
    mkdir $Home\Documents\WindowsPowerShell\Modules
    $p = [Environment]::GetEnvironmentVariable('PSModulePath','User') 
    #Add the new path to the $p variable. Begin with a semi-colon separator. 
    $p += ";$Home\Documents\WindowsPowerShell\Modules" 
    #Add the paths in $p to the PSModulePath value. 
    [Environment]::SetEnvironmentVariable('PSModulePath',$p,'User') 
  
} 