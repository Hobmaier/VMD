# SYNOPSIS
This module provisions Virtual Machines accross Azure and Hyper-V. It's a set of multiple VMs.

# DESCRIPTION
Use this script to provision / duplicate demo environments (which ware not generalized). It copies vhd files directly and creates new VM definition in Azure. My case was SharePoint environment including (AD, SQL, SharePoint 2013 & 2016, Office Online, Exchange, Windows Client). This can be useful within companies to distribute same test or dev environment.
New is it to download those vhd only and then to create VMs on Hyper-V

# EXAMPLE
./Import-Module Contoso
connect-Contoso
New-ContosoInstance -Prefix QA

# NOTES
All examples based on SharePoint with dependency on AD, SQL, SharePoint, Mailserver, Office Online...

# Getting Started
1. Download this repository and install AzureRM Module
2. Create your demo environment on Azure (Virtual Machines), based on multiple machines (No Managed Disks in the template). Currently there's a fixed naming schema, but feel free to contribute to this project:
  - Contoso-AD
  - Contoso-SQL
  - Contoso-SP2013
  - Contoso-SP2016
  - Contoso-Office
  - Contoso-Exchange
3. Change the Contoso\VMD-Config.xml and add 
  - Your Storage Accounts, Design is to put all the OS disks in one storage account and to distribute all SQL data disks accross four data storage accounts (for IOPS performance)
  - Add your demo environments Domain Admin Account including domain, user and password
4. Run "Install-VMDPSModule" to install the PowerShell Module locally, for Azure Cloud Shell consider this article: https://www.hobmaier.net/2018/02/azure-cloud-shell.html
5. Now use this Module to manage your demo environment, such as
  - New-VMDInstance to clone the complete environment into the same or different tenant or to download all VHD to further use it on Hyper-V (Yes, Hyper-V is also supported e.g. template on Azure, deploy on Azure and Hyper-V - spread your VMs...)
  - Start-VMD to start a defined set of VMs, in the correct order
  - Stop-VMD to stop them in the right order

# LINK
My Blog and Podcast about SharePoint, Office 365 and Azure: https://www.hobmaier.net

# History
V3.6
- New: Linux Cloud Shell Support and therefore Refactoring and new ContosoFunctions.ps1 and two releases of this module (Windows and Linux)
- New: Changed cmdlet Reload-Contoso to Reset-VMDAuthentication (supported verb)

V3.5
- New: Store AzureRM Account into JSON file and load it 

V3.4
- Fix: Switch -UseManagedDisks now uses correct VM Name (corrected variable)
- Fix: Installing PowerShell Module will now be correct an place it in subfolder Contoso, create it if not exist

V3.3
- Fix: Hyper-V Start, check if VM already runs before waiting for nothing
- New: Changed Storage Account to WestEurope (xml config)

V3.2
- New: Updated Azure Modules Import to make it Azure Cloud Shell compatible
- Fix: Switch -UseManagedDisks corrected ResourceGroup variable name
- Fix: Switch -UseManagedDisks stop-azurermvm now with -force (without prompt)

V3.1
- New: Support Hyper-V Differencing Disks using switch -UseDifferencingDisks while creation
- New: Added detailed help for New-ContosoInstance
- Fix: Some minor Fixes e.g. Azure by default
- Fix: Default Azure now WestEU because source VHD files reside there
- Fix: Default Azure for several commands
- Changed: Source files now in WestUS, new Storage Accounts and Keys now from XML

V3.0
- New: Network Security Rule enabled by default (only RDP inbound)
- New: Hyper-V Provisioning (Use 
  1. New-ContosoInstance -downloadonly 
  2. New-ContosoInstance -path ... )
- New: Hyper-V Post Provisioning Tasks such as:
  1.  Network Settings
  2. Pagefile Settings
  3. Start/Stop
- New: Requires new Azure PowerShell (See PreReq)

# Contribute
If you have any ideas or would like to contribute, please feel free to add a GitHub Pull Request.