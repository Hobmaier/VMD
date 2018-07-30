<#

.SYNOPSIS
This is a helper script for deployment process

.DESCRIPTION
Use this script to build psd1 file, install to local PowerShell Module directory and update File paths including Linux
#> 

param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_})]
    $AzureStorageConfigXMLPath
)
function Use-RunAs
{   
    # Check if script is running as Adminstrator and if not use RunAs
    # Use Check Switch to check if admin
    
    param([Switch]$Check)
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()`
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        
    if ($Check) { return $IsAdmin }    

    if ($MyInvocation.ScriptName -ne "")
    { 
        if (-not $IsAdmin) 
        { 
            try
            { 
                $arg = "-file `"$($MyInvocation.ScriptName)`""
                Start-Process "$psHome\powershell.exe" -Verb Runas -ArgumentList $arg -ErrorAction 'stop' 
            }
            catch
            {
                Write-Warning "Error - Failed to restart script with runas" 
                break              
            }
            exit # Quit this session of powershell
        } 
    } 
    else 
    { 
        Write-Warning "Error - Script must be saved as a .ps1 file first" 
        break 
    } 
}

function New-VMDManifest
{
    New-ModuleManifest -Path $PSScriptRoot\VMD\VMD.psd1 `
        -RootModule VMD.psm1 `
        -Author 'Dennis Hobmaier' `
        -CompanyName 'Solutions2Share' `
        -Description 'Manage VMD VMs in Azure' `
        -ModuleVersion '3.6' `
        -RequiredModules 'AzureRM.Profile','AzureRM.Storage','AzureRM.Compute', 'AzureRM.Network', 'AzureRM.Resources' `
        -FunctionsToExport 'Connect-VMD','Start-VMD','Stop-VMD','Select-VMDAzureSubscription',`
            'New-VMDInstance','Get-VMDStatus','Get-VMDResourceGroup','Select-VMDResourceGroup','New-VMDVM', `
            'Set-VMNetworkConfiguration','Set-Pagefile','Reset-VMDAuthentication' `
        -CmdletsToExport '' `
        -AliasesToExport ''
}
function New-VMDManifestLinux
{
    New-ModuleManifest -Path $PSScriptRoot\VMDACC\VMD.psd1 `
        -RootModule VMD.psm1 `
        -Author 'Dennis Hobmaier' `
        -CompanyName 'Solutions2Share' `
        -Description 'Manage VMD VMs in Azure' `
        -ModuleVersion '3.6' `
        -RequiredModules 'AzureRM.Profile.Netcore','AzureRM.Storage.Netcore','AzureRM.Compute.Netcore', 'AzureRM.Network.Netcore', 'AzureRM.Resources.Netcore' `
        -FunctionsToExport 'Connect-VMD','Start-VMD','Stop-VMD','Select-VMDAzureSubscription',`
            'New-VMDInstance','Get-VMDStatus','Get-VMDResourceGroup','Select-VMDResourceGroup','New-VMDVM', `
            'Set-VMNetworkConfiguration','Set-Pagefile','Reset-VMDAuthentication' `
        -CmdletsToExport '' `
        -AliasesToExport ''
}


#Check if admin - no need, running user based installation
#Use-RunAs

Write-host 'Create new Manifest'
New-VMDManifest
Write-host 'Create new ManifestLinux'
New-VMDManifestLinux
Copy-Item -path $PSScriptRoot\VMD\VMDFunctions.ps1 -Destination $PSScriptRoot\VMDACC\VMDFunctions.ps1

#"Script Running As Administrator"
Write-host 'Installing VMD PowerShell Module'
# Global Install
# Copy-Item $PSScriptRoot\UDESetup $Env:ProgramFiles\WindowsPowerShell\Modules\ -Force -Recurse


$paths = $env:PSModulePath.Split(';')
foreach ($path in $paths)
{
    if (($path.Indexof('\Users\') -gt 0) -and ($path.Indexof('OfficeDevPnP') -lt 0) -and ($path.Indexof('SharePointPnPPowerShellOnline') -lt 0) -and ($path.Indexof('.vscode') -lt 0))
    {
         Write-Host 'Install PowerShell Module to ' $path
         Copy-Item $PSScriptRoot\VMD $path -Force -Recurse -ErrorAction stop
         If ($AzureStorageConfigXMLPath) {Copy-Item $AzureStorageConfigXMLPath -Destination $path -Force}
    }
}

Write-host 'Done' -ForegroundColor Green

Start-Sleep -Seconds 5