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
. "$PSScriptRoot/VMDFunctions.ps1"

#Load Azure
Write-Host 'Import Azure Modules'
import-module AzureRM.Network.Netcore -ErrorAction Stop
Import-Module AzureRM.Storage.Netcore -ErrorAction Stop
Import-Module AzureRM.Compute.Netcore -ErrorAction Stop
Import-Module AzureRM.Resources.Netcore -ErrorAction Stop
Import-Module AzureRM.Profile.Netcore -ErrorAction Stop

Write-Host 'Login to Azure Portal'
Write-Host '  Use "Connect-VMD" to login'
Write-Host '  Use "Start-VMD" to start your instance'
Write-Host '  Use "Stop-VMD" to stop your instance'
write-host 'Run "get-command -module VMD" for all available command'

#Load XML for storage config
[xml]$XMLconfig = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath 'VMD-Config.xml') -ErrorAction Stop
