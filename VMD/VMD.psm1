<#

.SYNOPSIS
This module provisions Virtual Machines accross Azure and Hyper-V

.DESCRIPTION
Use this script to provision / duplicate demo environments (which ware not generalized). It copies vhd files directly and creates new VM definition in Azure.
New is it to download those vhd only and then to create VMs on Hyper-V

.EXAMPLE
./Import-Module VMD
connect-VMD
New-VMDInstance -Prefix QA

.NOTES
All examples based on SharePoint with dependency on AD, SQL, SharePoint, Mailserver, Office Online...

.LINK
https://www.hobmaier.net

#>
Write-Host 'VMD Module Version V 3.6'
. $PSScriptRoot\VMDFunctions.ps1

# Release history has moved to readme.md

#Load Azure
Write-Host 'Import Azure Modules'
import-module AzureRM.Network -ErrorAction Stop
Import-Module AzureRM.Storage -ErrorAction Stop
Import-Module AzureRM.Compute -ErrorAction Stop
Import-Module AzureRM.Resources -ErrorAction Stop
Import-Module AzureRM.Profile -ErrorAction Stop

Write-Host 'Login to Azure Portal'
Write-Host '  Use "Connect-VMD" to login'
Write-Host '  Use "Start-VMD" to start your instance'
Write-Host '  Use "Stop-VMD" to stop your instance'
write-host 'Run "get-command -module VMD" for all available command'
#import-module CredentialManager

#For Hyper-V check if local admin
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()`
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
If (!$IsAdmin)
{ 
    Write-Host "`n"'No local admin. Hyper-V operations might fail, please restart PowerShell using "Run As Administrator"'
}

#Load XML for storage config
[xml]$XMLconfig = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath 'VMD-Config.xml') -ErrorAction Stop
