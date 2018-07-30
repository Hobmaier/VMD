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

# LINK
https://www.hobmaier.net

# History
V3.6
- New: Linux Cloud Shell Support and therefore Refactoring and new ContosoFunctions.ps1 and two releases of this module (Windows and Linux)

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
 -New: Network Security Rule enabled by default (only RDP inbound)
 -New: Hyper-V Provisioning (Use 
            1. New-ContosoInstance -downloadonly 
            2. New-ContosoInstance -path ... )
-New: Hyper-V Post Provisioning Tasks such as:
    a. Network Settings
    b. Pagefile Settings
    c. Start/Stop
-New: Requires new Azure PowerShell (See PreReq)
