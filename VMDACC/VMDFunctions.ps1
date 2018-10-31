Write-Debug 'VMDFunctions entry'
function Connect-VMD
{
    param(
        # Azure SubscriptionID
        [Parameter(Mandatory = $false)]
        [guid]
        $AzureSubscriptionID
    )
    #Try to get it through credential manager
    #As it only supports ORG accounts and we at S2S only have Live IDs, disable creating it for the moment.
    <#
    $cred = Get-StoredCredential -Target VMD -ErrorAction SilentlyContinue
    if (!$cred)
    {
        #'First time or no credential, so ask to create it'

        Write-host 'No stored credentials found, creating it...'
        $credresult = get-credential -Message 'Please provide your Azure ORG Login Details @solutions2share.net' | New-StoredCredential -Target VMD
        $cred = Get-StoredCredential -Target VMD
    }
    try 
    {
        #Use credential manager
        Write-Host 'Use Credential Manager, login to tentant 61ebd848-8fe5-48eb-a220-7b16175d83df'
        Login-AzureRmAccount -Credential $cred -TenantId 61ebd848-8fe5-48eb-a220-7b16175d83df -ErrorAction Stop
    }
    catch
    {
        #Fallback old school and ask for credentials
        Write-Host '...failed. No ask for credentials' -ForegroundColor Yellow
        Login-AzureRmAccount
    }
    If you remove this comment, remove the next line as well#>
    $filePath = $PSScriptRoot + "/VMDAzureProfileCached.json";
    # Check if Cached Prifle exists
    if (![System.IO.File]::Exists($filePath)){
        Write-host 'No stored AzureProfile found, creating it...'
        #if no profile exists, login to azure and save it to the module folder
        Login-AzureRmAccount
        Save-AzureRmContext -Path $filePath
    }
    else{
        Write-host 'Stored AzureProfile found'
        #load cached profile
        Import-AzureRmContext -Path $filePath
        
        #If using ADFS this doesn't work and it wouldn't return any subscriptions
        If (!(Get-AzureRMSubscription)) { 
            #Log-in again and it should be fine
            Login-AzureRMAccount 
        }

    }

    # Get all subscriptions
    # Get-AzureRmSubscription

    #Set default subscription for current session
    #Get-AzureRmSubscription -SubscriptionName 'Visual Studio Ultimate with MSDN' | Select-AzureRmSubscription
    if (!$AzureSubscriptionID)
    {
        $Subscription = Select-VMDAzureSubscription
    } else {
        $Subscription = Select-VMDAzureSubscription -AzureSubscriptionID $AzureSubscriptionID
    }
    # $AzureResourceGroup = Select-VMDResourceGroup
}
function Reset-VMDAuthentication
{
    $filePath = $PSScriptRoot + "/VMDAzureProfileCached.json";
    Login-AzureRmAccount
    Save-AzureRmProfile -Force -Path $filePath
}

function Start-VMD
{
    [CmdletBinding(DefaultParameterSetName="Azure")]     
    param(
        [Parameter(Mandatory=$false,ParameterSetName='Azure')]
        [string]
        $AzureResourceGroup,
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('SQLonly','SQLandClient','SP2013UseCases','SP2013WithOfficeOnline','SP2013WithOfficeMail','SP2016UseCases','SP2016WithOfficeOnline','SP2016WithOfficeMail','SP2019UseCases','SP2019WithOfficeOnline','SP2019WithOfficeMail','All')]
        [string]
        $Scenario,
        [Parameter(Mandatory=$false,ParameterSetName='HyperV')]
        [switch]
        $HyperV,
        [Parameter(Mandatory=$false,ParameterSetName='HyperV')]
        [ValidateNotNullOrEmpty()]
        [string]
        $HyperVPrefix
    )
    
    If ((!$AzureResourceGroup) -and (!$HyperV))
    {
        $AzureResourceGroup = Select-VMDResourceGroup
    }
    If (!$Scenario)
    {
        $Scenario = Select-VMDScenario
    }
    $StartTime = Get-Date
    Write-Host $StartTime
    If (!$HyperV)
    {
        Get-VMDStartSequence -AzureResourceGroup $AzureResourceGroup -Scenario $Scenario | ForEach-Object -Process {
            if (($AzureVM = Get-azureRmVm -Name $_ -ResourceGroupName $AzureResourceGroup -Status -ErrorAction Ignore) -ne $null) 
            {
                foreach ($VMStatus in $AzureVM.Statuses)
                { 
                    if(($VMStatus.Code.CompareTo("PowerState/deallocated") -eq 0) -or ($VMStatus.Code.CompareTo('PowerState/stopped') -eq 0))
                    {
                        Write-Host 'Start VM ' $AzureVM.Name 
                        $StartResult = Start-AzureRmVM -Name $AzureVM.Name -ResourceGroupName $AzureResourceGroup -ErrorAction Stop -Verbose
                        Write-Host 'Result: ' $StartResult.Status
                        #If domain controller is slow, wait before starting next VM (round about 3 minutes in total)
                        If ($AzureVM.Name.LastIndexOf('Contoso-AD') -gt -1) 
                        { 
                            Write-Host 'DC - wait additional 60 Seconds'
                            Start-Sleep -Seconds 60
                            $MidTime = Get-Date
                            Write-Host 'Time now ' $MidTime
                            Write-Host 'Starting VM took ' $MidTime.Subtract($StartTime)                        
                        } elseif ($AzureVM.Name.LastIndexOf('Contoso-SQL') -gt -1) 
                        {
                            Write-Host 'Wait 30 seconds before continue'
                            Start-Sleep -Seconds 30
                        }                   
                    }
                }
            }
        } 
    } else {
        #HyperV    
        If (!$IsAdmin)
        { 
            Write-Host "No local admin. Hyper-V operations might silently fail" -ForegroundColor Yellow
        }        
        Import-Module Hyper-V -ErrorAction Stop
        Get-VMDStartSequence -HyperVPrefix $HyperVPrefix -Scenario $Scenario | ForEach-Object -Process {
            if (($VM = Get-VM -Name $_ -ErrorAction SilentlyContinue) -ne $null)
            {
                Write-Host "`nStart Hyper-V VM" $VM.Name
                If (!$VM.State -eq 'Running')
                {
                    Start-VM -name $VM.Name
                    while ($VM.Heartbeat -ne 'OkApplicationsHealthy')
                    {
                        Start-Sleep -Seconds 10
                        Write-Host '.' -NoNewline
                    }
                    Write-Host "`nWait additional 120 seconds"
                    Start-Sleep -Seconds 120
                } else {
                    Write-Host '  Already running'
                }
            }
        }
        #Cleanup
        $VM = $null
    }
    

    $EndTime = Get-Date
    Write-Host 'Starting all VMs took ' $EndTime.Subtract($StartTime)
}

function Stop-VMD
{    
    [CmdletBinding(DefaultParameterSetName="Azure")]         
    param(
        [Parameter(Mandatory=$false,ParameterSetName='Azure')]
        [string]
        $AzureResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='HyperV')]
        [switch]
        $HyperV,
        [Parameter(Mandatory=$false,ParameterSetName='HyperV')]
        [ValidateNotNullOrEmpty()]
        [string]
        $HyperVPrefix
    )
    If ((!$AzureResourceGroup) -and (!$HyperV))
    {
        $AzureResourceGroup = Select-VMDResourceGroup
    }    
    $StartTime = Get-Date
    Write-Host $StartTime
    If (!$HyperV)
    {
        Get-VMDStopSequence -AzureResourceGroup $AzureResourceGroup | ForEach-Object -Process {
            if (($AzureVM = Get-azureRmVm -Name $_ -ResourceGroupName $AzureResourceGroup -Status -ErrorAction Ignore) -ne $null) 
            {
                foreach ($VMStatus in $AzureVM.Statuses)
                { 
                    if(($VMStatus.Code.CompareTo("PowerState/running") -eq 0) -or ($VMStatus.Code.CompareTo('PowerState/stopped') -eq 0)) 
                    {
                        Write-Host 'Stop VM ' $AzureVM.Name 
                        $StopResult = Stop-AzureRmVM -Name $AzureVM.Name -ResourceGroupName $AzureResourceGroup -ErrorAction stop -Verbose -force
                        Write-Host 'Result ' $StopResult.Status
                    }
                }
            }
        }   
    } else {
        #HyperV    
        If (!$IsAdmin)
        { 
            Write-Host "No local admin. Hyper-V operations might silently fail" -ForegroundColor Yellow
        }

        Import-Module Hyper-V -ErrorAction Stop
        Get-VMDStopSequence -HyperVPrefix $HyperVPrefix | ForEach-Object -Process {
            if (($VM = Get-VM -Name $_ -ErrorAction SilentlyContinue) -ne $null)
            {
                Write-Host "`nStop Hyper-V VM" $VM.Name
                Stop-VM -name $VM.Name
                while ($VM.state -ne 'Off')
                {
                    Start-Sleep -Seconds 10
                    Write-Host '.' -NoNewline
                }
            }
        }
        #Cleanup
        $VM = $null
    }
    
    $EndTime = Get-Date
    Write-Host 'Stopping all VMs took ' $EndTime.Subtract($StartTime)
}

function Select-VMDAzureSubscription
{
    [cmdletBinding()]
    param(
        # AzureSubscriptionID
        [Parameter(Mandatory = $False)]
        [guid]
        $AzureSubscriptionID
    )
    $Subscriptions = Get-AzureRmSubscription
    if (!$AzureSubscriptionID)
    {
        # if no parameter was passed
        $i = 1
        foreach ($Subscription in $Subscriptions) 
        {
            # Bug in Azure PowerShell >4.x $Subscription.SubscriptionName is now $Subscription.Name
            Write-Host $i '    ' $Subscription.SubscriptionId '    ' $Subscription.Name -ForegroundColor White
            $i++
        }
        
        $Prompt = Read-host "Select your Azure SubscriptionId by number"
        # Bug in Azure PowerShell 1.5 / should be fixed in 1.5.1 but is not. Subscription can be selected by name only in some cases.
        try
        {
            $Result = Select-AzureRmSubscription -SubscriptionId $Subscriptions[($prompt -1)] -ErrorAction Stop
        }
        catch
        {
            $Result = Select-AzureRmSubscription -SubscriptionName ($Subscriptions[($prompt -1)].SubscriptionName) -ErrorAction Stop
        }
        
        Write-Host 'Subscription selected ' $Subscriptions[($prompt -1)] -ForegroundColor Green
    } else {
        #Only if parameter was passed
        $Result = Select-AzureRmSubscription -SubscriptionId $AzureSubscriptionID -ErrorAction Stop
        Write-Host 'Subscription selected ' $AzureSubscriptionID -ForegroundColor Green
    }
    return $Result
}

function New-VMDInstance
{
    <#
    .SYNOPSIS
        Provisions a new set of virtual machines to Azure or local Hyper-V

    .DESCRIPTION
        Define a destination environment and a new clone / copy will be created

    .PARAMETER Prefix
        Prefix will be added in front of VM names. E.g. base is VMD-AD = Prefix-VMD-AD

    .PARAMETER DeployMinimalSet
        Only Provisions AD, SQL and SP2016 VMs

    .PARAMETER LocationName
        Azure Region to deploy to - default North EU
    .PARAMETER DownloadOnly
        Only Download VHD files and skip creation of anything
    .PARAMETER DeployToLocalHyperV
        Requires that DownloadOnly already run. It will create VMs on a local Hyper-V environment
    .PARAMETER Path
        Specifies Download destination in case of -DownloadOnly or
        It contains the previous downloaded files used to create VMs using switch -DeployToLocalHyperV
    .PARAMETER CreateWithMinRAM
        When using with Switch -DeployToLocalHyperV it creates VMs using lowest possible RAM usage
    .PARAMETER UseManagedDisks
        Use new Azure Managed Disks. Currently VMs get converted at the end of the provisioning
    .PARAMETER SubnetOctet
        On Hyper-V you can specify mutliple subnets (useful when using multiple deployments on one Hyper-V)
        Default = 10.0.0.0/24, This parameter used to set 10.0.x.0/24, eg. 10.0.1.0/24. It applies to Hyper-V Internal network and VM IPs.
    .PARAMETER UseDifferencingDisks
        On Hyper-V instead of using a full blown VHD copy (in my case 800 GB), it will create differencing disks. Useful if running multiple copies on one Hyper-V Host.
    .PARAMETER DifferencingVHDPath
        Use Path provided instead of default Hyper-V VHD folder.

    .EXAMPLE
        New-VMDInstance -Prefix DEV
        Easiest one, create a new copy in Azure, previous selected subscription, Prefix will be the unique Identifier for Resource Groups, VM Names etc.
    .EXAMPLE
        New-VMDInstance -Prefix DEV -UseManagedDisks -DeployMinimalSet
        Creates VM in Azure, adds Prefix DEV, converts disks to Managed Disks and only creates three VMs AD, SQL, SP2016.
    .EXAMPLE
        New-VMDInstance -Prefix DEV -UseManagedDisks -LocationName WestEurope -DeployMinimalSet
        Creates VM in Azure, adds Prefix DEV, converts disks to Managed Disks, Azure Location WestEurope (costs may apply when copy), only creates three VMs AD, SQL, SP2016.
    .EXAMPLE
        New-VMDInstance -DownloadOnly -Path c:\Downloads
        Simply downloads all VHD files from all VMs (Golden Image) to Path specified.
    .EXAMPLE
        New-VMDInstance -DeployToLocalHyperV -Path c:\hypervVHD
        Creates new Hyper-V VMs. VHD files must be located in c:\hypervVHD.
    .EXAMPLE
        New-VMDInstance -DeployToLocalHyperV -Path c:\hypervVHD -CreateWithMinRAM -UseSubnetOctet 1 -UseDifferencingDisks        
        Creates new Hyper-V VMs. VHD files must be located in c:\hypervVHD which won't be modified. Instead a new Differencing Disk (aka Snapshot) will be created, the VHDs in Path gets the Parent Disks which can be shared by multiple VMs.
    #>
    [CmdletBinding(DefaultParameterSetName="Azure")]    
    param(
        [Parameter(Mandatory = $false)]
            [string]
        $Prefix,

        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
            [switch]
        $DeployMinimalSet,

        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
            [string]
        $LocationName = "westeurope",

        [Parameter(Mandatory = $false, ParameterSetName = 'Download')]
            [switch]
        $DownloadOnly,

        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
            [switch]
        $DeployToLocalHyperV,

        [Parameter(Mandatory = $false, ParameterSetName = 'Download')] #test if mandatory can be set to $true
            [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
            [ValidateScript({Test-Path $_})]
            [string]
        $Path,

        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
            [switch]
        $CreateWithMinRAM,

        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
            [switch]
        $UseManagedDisks,

        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
            [Int]
        $SubnetOctet = 0,

        [Parameter(Mandatory=$false, ParameterSetName = 'HyperV')]
            [switch]
        $UseDifferencingDisks,
        
        [Parameter(Mandatory=$false, ParameterSetName = 'HyperV')]
            [string]
            [ValidateScript({Test-Path $_})]
        $DifferencingVHDPath
    )

    

    #Get Input
    #SubscriptionId
    if ((!$Prefix) -and (!$DownloadOnly) -and (!$DeployToLocalHyperV)) 
    {
        #Prefix
        Write-host -ForegroundColor white -Object 'Please specify a Prefix such as Test or DEV. Prefix will be added in all resources and names, e.g. DEV-Contoso-AD'
        $Prefix = Read-Host -Prompt 'Enter Prefix: '
    }
    #Virtual Machine Definition
    If ($DeployMinimalSet)
    {
        $VirtualMachines = @('AD', 'Standard_A0', "10.0.$SubnetOctet.10"), `
                        @('SQL','Standard_DS2_v2', "10.0.$SubnetOctet.11"), `
                        @('SP2016','Standard_D4s_v3', "10.0.$SubnetOctet.13")
    } else {
        $VirtualMachines = @('AD', 'Standard_A0', "10.0.$SubnetOctet.10"), `
                        @('SQL','Standard_DS2_v2', "10.0.$SubnetOctet.11"), `
                        @('SP2013','Standard_D4s_v3', "10.0.$SubnetOctet.12"), `
                        @('SP2016','Standard_D4s_v3', "10.0.$SubnetOctet.13"), `
                        @('SP2019','Standard_D4s_v3', "10.0.$SubnetOctet.17"), `
                        @('Office', 'Standard_DS1_v2', "10.0.$SubnetOctet.14"), `
                        @('Client', 'Standard_DS1_v2', "10.0.$SubnetOctet.16"), `
                        @('Mail', 'Standard_A2m_v2', "10.0.$SubnetOctet.15")
    }
    # Standard_D4s_v3 = 4 vCores, 16 GB RAM, Premium Disk supported ~ 150 €/month
    # Standard_DS11_v2 = 2 vCores, 14 GB RAM ~ 120 €/month
    # Standard_DS2_v2 = 2 vCores, 7 GB RAM ~ 85 €/month
    # Standard_A0 = 1 vCore, 0,75 GB RAM ~ 12 €/month
    # Standard_DS1_v2 = 1 vCore, 3,5 GB RAM ~ 42 €/month
    # Standard_A2m_v2 = 2 vCore, 16 GB RAM, NO Premium Disk supported ~ 78 €/month


    #Should be in the same subnet than above
    $HyperVHostVMIP = "10.0.$SubnetOctet.1"

    
    $StartTime = Get-Date
    ## VM Account
    # Credentials for Local Admin account you created in the sysprepped (generalized) vhd image
    $VMLocalAdminUser = $XMLconfig.VMDup.GlobalConfiguration.Username.Name
    $VMLocalAdminSecurePassword = ConvertTo-SecureString $XMLconfig.VMDup.GlobalConfiguration.Password.Value -AsPlainText -Force 
    $Credentials = New-Object System.Management.Automation.PSCredential `
        -ArgumentList $VMLocalAdminUser, $VMLocalAdminSecurePassword 
    ## Azure Account
    $InstanceName = $Prefix + '-Contoso'
    Write-Host 'Instance Name ' $InstanceName
    $InstanceAzureFriendlyName = $InstanceName.ToLower().Replace('-','')
    Write-Verbose $InstanceAzureFriendlyName
    $SubnetAddressPrefix = "10.0.$SubnetOctet.0/24"
    $VnetAddressPrefix = "10.0.$SubnetOctet.0/24"

    $XMLconfig.VMDup.StorageAccounts.StorageAccount | ForEach-Object { 
        $saName = $_.Name
        $saURL = $_.StorageAccountURL
        $saKey = $_.StorageAccountKey
        switch ($saName) {
            OS { 
                $SourceStorageURLOS = $saURL
                $SourceStorageKeyOS = $saKey
             }
            Data1 {
                $SourceStorageURLData1 = $saURL
                $SourceStorageKeyData1 = $saKey
            }
            Data2 {
                $SourceStorageURLData2 = $saURL
                $SourceStorageKeyData2 = $saKey
            }
            Data3 {
                $SourceStorageURLData3 = $saURL
                $SourceStorageKeyData3 = $saKey
            }
            Data4 {
                $SourceStorageURLData4 = $saURL
                $SourceStorageKeyData4 = $saKey
            }
            Default {
                Write-Host -ForegroundColor Red 'ERROR, no Storage Accounts found in XML configuration file'
            }
        }
    }

    # It is required in order to run a client VM with efficiency and high performance.    
    
    if (!$DownloadOnly)
    {
        if (!$DeployToLocalHyperV)
        {
            #Create Resource Group
            $ResourceGroup = New-AzureRmResourceGroup -Name $InstanceName -Location $LocationName
            Write-host 'Your resource group - remember it' $ResourceGroup.ResourceGroupName -ForegroundColor Green

            write-host 'Create VirtualNetworkSubnetConfig'
            $SingleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $InstanceName -AddressPrefix $SubnetAddressPrefix -ErrorAction Stop
            Write-Host 'Create VirtualNetwork'
            $Vnet = New-AzureRmVirtualNetwork -Name $InstanceName -ResourceGroupName $ResourceGroup.ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $SingleSubnet -DnsServer '10.0.0.10' -ErrorAction Stop
            
            Write-Host 'Create Storage account OS'
            $VMStorageOS = New-AzureRmStorageAccount -Location $LocationName -Name ($InstanceAzureFriendlyName + 'os') -ResourceGroupName $ResourceGroup.ResourceGroupName -Type Standard_LRS -ErrorAction Stop
            #Get Storage Account Key
            $DestStorageKeyOS = Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup.ResourceGroupName -Name $VMStorageOS.StorageAccountName
            Write-Host 'Create Storage account Data1'
            $VMStorageData1 = New-AzureRmStorageAccount -Location $LocationName -Name ($InstanceAzureFriendlyName + 'data1') -ResourceGroupName $ResourceGroup.ResourceGroupName -Type Standard_LRS -ErrorAction Stop
            $DestStorageKeyData1 = Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup.ResourceGroupName -Name $VMStorageData1.StorageAccountName
            Write-Host 'Create Storage account Data2'
            $VMStorageData2 = New-AzureRmStorageAccount -Location $LocationName -Name ($InstanceAzureFriendlyName + 'data2') -ResourceGroupName $ResourceGroup.ResourceGroupName -Type Standard_LRS -ErrorAction Stop
            $DestStorageKeyData2 = Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup.ResourceGroupName -Name $VMStorageData2.StorageAccountName
            Write-Host 'Create Storage account Data3'
            $VMStorageData3 = New-AzureRmStorageAccount -Location $LocationName -Name ($InstanceAzureFriendlyName + 'data3') -ResourceGroupName $ResourceGroup.ResourceGroupName -Type Standard_LRS -ErrorAction Stop
            $DestStorageKeyData3 = Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup.ResourceGroupName -Name $VMStorageData3.StorageAccountName
            Write-Host 'Create Storage account Data4'
            $VMStorageData4 = New-AzureRmStorageAccount -Location $LocationName -Name ($InstanceAzureFriendlyName + 'data4') -ResourceGroupName $ResourceGroup.ResourceGroupName -Type Standard_LRS -ErrorAction Stop
            $DestStorageKeyData4 = Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup.ResourceGroupName -Name $VMStorageData4.StorageAccountName
            
            #new container 'vhds'
            Write-Host 'Create vhds containers'
            Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup.ResourceGroupName -StorageAccountName $VMStorageData1.StorageAccountName
            New-AzureStorageContainer -Name 'vhds' -Permission Off | Out-Null
            Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup.ResourceGroupName -StorageAccountName $VMStorageData2.StorageAccountName
            New-AzureStorageContainer -Name 'vhds' -Permission Off | Out-Null
            Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup.ResourceGroupName -StorageAccountName $VMStorageData3.StorageAccountName
            New-AzureStorageContainer -Name 'vhds' -Permission Off | Out-Null
            Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup.ResourceGroupName -StorageAccountName $VMStorageData4.StorageAccountName
            New-AzureStorageContainer -Name 'vhds' -Permission Off | Out-Null
            Set-AzureRmCurrentStorageAccount -ResourceGroupName $ResourceGroup.ResourceGroupName -StorageAccountName $VMStorageOS.StorageAccountName
            New-AzureStorageContainer -Name 'vhds' -Permission Off | Out-Null
        }
    }
    if (!$DeployToLocalHyperV)
    {
        #CopyBLOB
        Start-sleep -Seconds 2
        #OS 
        $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
        #Fix0002: Azcopy requires file path with "" because of spaces /Journal and Log as well and in order to run it, use & before the command
        $AZcopy = "& ""$AZcopy"""
        Write-Host 'AZCopy path:' $AZCopy
        $AZJournal = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.jnl')
        $AZJournal = """$AZJournal"""
        $AZVerboseLog = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.log')
        $AZVerboseLog = """$AZVerboseLog"""
        #Fix0001: Change in API (at least Azure PowerShell >=1.5)
        # Change $VMStorageOS.PrimaryEndpoints.Blob.AbsoluteUri to $VMStorageOS.PrimaryEndpoints.Blob
        # Change $DestStorageKeyOS.Key1 to $DestStorageKeyOS.Value[0]
        If (!$DeployMinimalSet)
        {
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$($VMStorageOS.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyOS.Value[0]) /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$Path /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"    
            }
            Write-host 'Copy vhd files'
            #& $AZcopy $AZprm
            #Write-host 'Debug ' $Azcopy
            Invoke-Expression $AZcopy -ErrorAction Stop
        } else {
            #Now copy individual files
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$($VMStorageOS.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyOS.Value[0]) /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-AD201615161334.vhd"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$Path /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-AD201615161334.vhd"
            }
            Write-host 'Copy vhd file for AD'
            #Write-host 'Debug ' $Azcopy
            Invoke-Expression $AZcopy -ErrorAction Stop        
            start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE
            
            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$($VMStorageOS.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyOS.Value[0]) /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-SQL201615163329.vhd"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$Path /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-SQL201615163329.vhd"
            }
            Write-host 'Copy vhd file for SQL'
            Invoke-Expression $AZcopy -ErrorAction Stop        
            start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE

            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$($VMStorageOS.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyOS.Value[0]) /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-SP2016201622215411.vhd"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLOS) /Dest:$Path /SourceKey:$($SourceStorageKeyOS) /S /Z:$($AZJournal) /V:$($AZVerboseLog) /Pattern:Contoso-SP2016201622215411.vhd"
            }
            Write-host 'Copy vhd file for SP2013'
            Invoke-Expression $AZcopy -ErrorAction Stop        
        }
        start-sleep -Seconds 10
        write-host 'Azcopy Exit code' $LASTEXITCODE
        
        if ($lastexitcode -eq 0)
        {
            #Data1
            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            Write-Host 'AZCopy path:' $AZCopy
            $AZJournal = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.jnl')
            $AZJournal = """$AZJournal"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLData1) /Dest:$($VMStorageData1.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyData1.Value[0]) /SourceKey:$($SourceStorageKeyData1) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLData1) /Dest:$Path /SourceKey:$($SourceStorageKeyData1) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            }
            Write-host 'Copy vhd files'
            #& $AZcopy $AZprm
            Invoke-Expression $AZcopy -ErrorAction Stop
            start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE
        }
        if ($lastexitcode -eq 0)
        {
            #Data2
            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            Write-Host 'AZCopy path:' $AZCopy
            $AZJournal = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.jnl')
            $AZJournal = """$AZJournal"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLData2) /Dest:$($VMStorageData2.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyData2.Value[0]) /SourceKey:$($SourceStorageKeyData2) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLData2) /Dest:$Path /SourceKey:$($SourceStorageKeyData2) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            }
            Write-host 'Copy vhd files'
            #& $AZcopy $AZprm
            Invoke-Expression $AZcopy -ErrorAction Stop
            start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE
        }
        if ($lastexitcode -eq 0)
        {
            #Data3
            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            Write-Host 'AZCopy path:' $AZCopy
            $AZJournal = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.jnl')
            $AZJournal = """$AZJournal"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLData3) /Dest:$($VMStorageData3.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyData3.Value[0]) /SourceKey:$($SourceStorageKeyData3) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLData3) /Dest:$Path /SourceKey:$($SourceStorageKeyData3) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            }
            Write-host 'Copy vhd files'
            #& $AZcopy $AZprm
            Invoke-Expression $AZcopy -ErrorAction Stop
            start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE
        }
        if ($lastexitcode -eq 0)
        {
            #Data4
            $AZcopy = $null
            $AZcopy = Join-Path -Path $PSScriptRoot -ChildPath 'Azcopy.exe'
            $AZcopy = "& ""$AZcopy"""
            Write-Host 'AZCopy path:' $AZCopy
            $AZJournal = Join-Path -Path $PSScriptRoot -ChildPath ($InstanceName + '.jnl')
            $AZJournal = """$AZJournal"""
            If (!$DownloadOnly)
            {
                $AZcopy += " /Source:$($SourceStorageURLData4) /Dest:$($VMStorageData4.PrimaryEndpoints.Blob)vhds /DestKey:$($DestStorageKeyData4.Value[0]) /SourceKey:$($SourceStorageKeyData4) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            } else {
                $AZcopy += " /Source:$($SourceStorageURLData4) /Dest:$Path /SourceKey:$($SourceStorageKeyData4) /S /Z:$($AZJournal) /V:$($AZVerboseLog)"
            }
            Write-host 'Copy vhd files'
            #& $AZcopy $AZprm
            Invoke-Expression $AZcopy -ErrorAction Stop
            Start-sleep -Seconds 10
            write-host 'Azcopy Exit code' $LASTEXITCODE
        }            
    }
    
    if (($LASTEXITCODE -eq 0) -and (!$DownloadOnly) -and (!$DeployToLocalHyperV))
    {   
        foreach ($VirtualMachine in $VirtualMachines)
        {
            if ($VirtualMachine[0] -eq 'SQL') {
                    Write-Host 'Create VM ' $InstanceName"-"$($VirtualMachine[0])
                    
                    $VM = New-VMDVM -InstanceName $InstanceName `
                    -VirtualMachinePartialName $VirtualMachine[0] `
                    -VMSize $VirtualMachine[1] `
                    -PrivateIPAddress $VirtualMachine[2] `
                    -SubnetID $Vnet.Subnets[0].Id `
                    -OSDiskUri "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-SQL201615163329.vhd" `
                    -LocationName $LocationName `
                    -Data1DiskUri "$($VMStorageData1.PrimaryEndpoints.Blob)vhds/Contoso-SQL-data1.vhd" `
                    -Data2DiskUri "$($VMStorageData2.PrimaryEndpoints.Blob)vhds/Contoso-SQL-data2.vhd" `
                    -Data3DiskUri "$($VMStorageData3.PrimaryEndpoints.Blob)vhds/Contoso-SQL-data3.vhd" `
                    -Data4DiskUri "$($VMStorageData4.PrimaryEndpoints.Blob)vhds/Contoso-SQL-data4.vhd"
                Write-host 'Success' $vm -ForegroundColor Green   
                Start-Sleep -Seconds 30                 
            } else {
                Write-Host 'Create VM ' $InstanceName"-"$($VirtualMachine[0])
                If ($VirtualMachine[0] -eq 'AD')
                {
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-AD201615161334.vhd"
                } elseif ($VirtualMachine[0] -eq 'SP2013') {
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-SP2013201618131334.vhd"
                } elseif ($VirtualMachine[0] -eq 'SP2016') {
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-SP2016201622215411.vhd"
                } elseif ($VirtualMachine[0] -eq 'SP2019'){
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-SP201920181023114007.vhd"
                } elseif ($VirtualMachine[0] -eq 'Office'){
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-Office2016822162630.vhd"
                } elseif ($VirtualMachine[0] -eq 'Mail'){
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/Contoso-Mail20170425162213.vhd"
                } elseif ($VirtualMachine[0] -eq 'Client'){
                    $OSDiskUri = "$($VMStorageOS.PrimaryEndpoints.Blob)vhds/DNS8-Contoso-CL20180517145702.vhd"
                } 

                $vm = New-VMDVM -InstanceName $InstanceName `
                        -VirtualMachinePartialName $VirtualMachine[0] `
                        -VMSize $VirtualMachine[1] `
                        -PrivateIPAddress $VirtualMachine[2] `
                        -SubnetID $Vnet.Subnets[0].Id `
                        -OSDiskUri $OSDiskUri `
                        -LocationName $LocationName
                Write-host 'Success' $vm -ForegroundColor Green
                If ($VirtualMachine[0] -eq 'AD')
                {
                    Start-Sleep -Seconds 150
                }
            }
            if ($UseManagedDisks)
            {
                Write-Host 'Now convert machines to use managed disks for better performance'
                Write-Host 'Stop VM first'
                $VMName = $InstanceName + "-" + $VirtualMachine[0]
                $null = Stop-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroup.ResourceGroupName -Force
                Write-Host 'Done. Now Convert it'
                $null = ConvertTo-AzureRmVMManagedDisk -VMName $VMName -ResourceGroupName $ResourceGroup.ResourceGroupName
                Write-Host 'Done. VM starting again - wait 2 minutes ;-)'
                Start-Sleep -Seconds 120
            }
        }
        
    } elseif ($DeployToLocalHyperV)
    {
        $ADVM = $null
        foreach ($VirtualMachine in $VirtualMachines)
        {
            Write-Host 'Create VM on Hyper-V' $InstanceName"-"$($VirtualMachine[0])
            
            New-VMDHyperV -Path $Path -Prefix $Prefix -VirtualMachinePartialName $VirtualMachine[0] -ConfigureMinimumRAM -HyperVHostIP $HyperVHostVMIP -UseDifferencingDisks -DifferencingVHDPath $DifferencingVHDPath
            
            Write-Host 'Done'
            $VMName = $InstanceName + "-" + $VirtualMachine[0]
            #Post Tasks on Hyper-V
            #Start Hyper-V VM
            Write-Host 'Start VM ' $VMName
            Start-VM -name $VMName -ErrorAction stop
            $VM = Get-VM -name $VMName
            #Use Heartbeat, which indicates OS is responding. State ist Running after turning on
            Write-Host "`nWait until OS is ready"
            while ($VM.Heartbeat -ne 'OkApplicationsHealthy')
            {
                Start-Sleep -Seconds 10
                Write-Host '.' -NoNewline
            }
                Write-Host "`nWait 120 more seconds to be safe and allow VM to configure it"
                Start-Sleep -Seconds 120

            Write-Host 'Post-Task Network'
            #Assign IP
            Get-VMNetworkAdapter -VMName $VMName | Set-VMNetworkConfiguration -IPAddress $VirtualMachine[2] -Subnet 255.255.255.0 -DefaultGateway 10.0.$SubnetOctet.1 -DNSServer 10.0.$SubnetOctet.10
            Write-Host 'Wait 30 seconds to allow Firewall to configure before connecting through WMI'
            Start-sleep -Seconds 30
            
            Write-Host 'Set Pagefile'
            #Pagefile - use IP to connect as no DNS
            Set-PageFile -Path C:\pagefile.sys -InitialSize 4096 -MaximumSize 8192 -Computer $VirtualMachine[2] -Credentials $Credentials            
            # Alternate
            # wmic computersystem set AutomaticManagedPagefile=True
            Write-Host 'Turn off VM - settings effective on next boot - except AD needed to authenticate' #Especially Set-Pagefile WMI
            If ($VirtualMachine[0] -ne 'AD')
            {
                Stop-VM -name $VMName | Out-Null
                while ($VM.State -ne 'Off')
                {
                    Start-Sleep -Seconds 10
                    Write-Host '.' -NoNewline
                }                
            } else {
                $ADVM = $VMName
            }
            
            
            #Activate Windows/Office
        }
        Write-Host "`nLast but not least, stop AD"
        Stop-VM name $ADVM | Out-Null
    }
    $EndTime = Get-Date
    Write-Host 'Deployment took ' $EndTime.Subtract($StartTime)
}



function New-VMDVM
{
    param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $InstanceName,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $VirtualMachinePartialName,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $VMSize,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $PrivateIPAddress,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $SubnetID,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $OSDiskUri,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]
        $LocationName,
            [Parameter(Mandatory = $false)]
            [string]
        $Data1DiskUri,
            [Parameter(Mandatory = $false)]
            [string]
        $Data2DiskUri,
            [Parameter(Mandatory = $false)]
            [string]
        $Data3DiskUri,
            [Parameter(Mandatory = $false)]
            [string]
        $Data4DiskUri
    )

    
    ## VM
    $VMName = $InstanceName + "-" + $VirtualMachinePartialName
    $VMAzureFriendlyName = $VMName.ToLower().Replace('-','')
    # Modern hardware environment with fast disk, high IOPs performance. 
    # Required to run a client VM with efficiency and performance
     
    $OSDiskCaching = "ReadWrite"
    $OSCreateOption = "Attach"

    ## Networking
    $DNSNameLabel = 's2s' + $VMAzureFriendlyName # mydnsname.westus.cloudapp.azure.com

    $PIP = New-AzureRmPublicIpAddress -Name $VMName -DomainNameLabel $DNSNameLabel -ResourceGroupName $ResourceGroup.ResourceGroupName -Location $LocationName -AllocationMethod Dynamic -ErrorAction Stop
    # Create an inbound network security group rule for port 3389
    $nsgRuleRDP = New-AzureRmNetworkSecurityRuleConfig `
        -Name default-allow-rdp  `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 1000 `
        -SourceAddressPrefix * `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange 3389 `
        -Access Allow 
    # Create a network security group
    $nsg = New-AzureRmNetworkSecurityGroup `
        -ResourceGroupName $ResourceGroup.ResourceGroupName `
        -Location $LocationName `
        -Name "$($VMName)nsg" `
        -SecurityRules $nsgRuleRDP           
    $NIC = New-AzureRmNetworkInterface -Name $VMName -ResourceGroupName $ResourceGroup.ResourceGroupName -Location $LocationName -SubnetId $SubnetID -PublicIpAddressId $PIP.Id -PrivateIpAddress $PrivateIPAddress -DnsServer '10.0.0.10' -NetworkSecurityGroupID $nsg.Id -ErrorAction Stop

    $VirtualMachine = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize -ErrorAction Stop
    
    # Disabled as we're using custom image and attach
    #$VirtualMachine = Set-AzureRmVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
    $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id -ErrorAction Stop

    $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name $VirtualMachinePartialName -VhdUri $OSDiskUri -Caching $OSDiskCaching -CreateOption $OSCreateOption -Windows -ErrorAction Stop
 

    if ($Data1DiskUri)
    {
        Add-AzureRmVMDataDisk -CreateOption attach -Name 'Contoso-SQL-data1' -VhdUri $Data1DiskUri -Caching None -vm $VirtualMachine -DiskSizeInGB 20 -Lun 0 -ErrorAction Stop
    }
    if ($Data2DiskUri)
    {
        Add-AzureRmVMDataDisk -CreateOption attach -Name 'Contoso-SQL-data2' -VhdUri $Data2DiskUri -Caching None -vm $VirtualMachine -DiskSizeInGB 20 -Lun 1 -ErrorAction Stop
    }
    if ($Data3DiskUri)
    {
        Add-AzureRmVMDataDisk -CreateOption attach -Name 'Contoso-SQL-data3' -VhdUri $Data3DiskUri -Caching None -vm $VirtualMachine -DiskSizeInGB 20 -Lun 2 -ErrorAction Stop
    }
    if ($Data4DiskUri)
    {
        Add-AzureRmVMDataDisk -CreateOption attach -Name 'Contoso-SQL-data4' -VhdUri $Data4DiskUri -Caching None -vm $VirtualMachine -DiskSizeInGB 20 -Lun 3 -ErrorAction Stop
    }     
    Write-Host 'Done building configuration, now create it'       
    $VMResult = New-AzureRmVM -ResourceGroupName $ResourceGroup.ResourceGroupName -Location $LocationName -VM $VirtualMachine -DisableBginfoExtension -Verbose -ErrorAction Stop
    return $VMResult.StatusCode
}

function Get-VMDStartSequence 
{
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
        [string]
        $AzureResourceGroup,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('SQLonly','SQLandClient','SP2013UseCases','SP2013WithOfficeOnline','SP2013WithOfficeMail','SP2016UseCases','SP2016WithOfficeOnline','SP2016WithOfficeMail','SP2019UseCases','SP2019WithOfficeOnline','SP2019WithOfficeMail','All')]
        [string]
        $Scenario,
        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
        [string]
        $HyperVPrefix
    )
    if ($AzureResourceGroup) { $Prefix = $AzureResourceGroup.substring(0,$AzureResourceGroup.LastIndexOf('-') +1)}
    if ($HyperVPrefix) {$Prefix = "$($HyperVPrefix)-"}

    switch ($Scenario) {
        SQLonly { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL") }
        SQLandClient { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-Client") }
        SP2013UseCases {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2013")}
        SP2013WithOfficeOnline {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2013", "$($Prefix)Contoso-Office")}
        SP2013WithOfficeMail {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2013", "$($Prefix)Contoso-Office", "$($Prefix)Contoso-Mail")}
        SP2016UseCases {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2016")}
        SP2016WithOfficeOnline {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2016", "$($Prefix)Contoso-Office")}
        SP2016WithOfficeMail {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2016", "$($Prefix)Contoso-Office", "$($Prefix)Contoso-Mail")}
        SP2019UseCases { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2019") }
        SP2019WithOfficeOnline { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2019", "$($Prefix)Contoso-Office") }
        SP2019WithOfficeOnlineAndClient { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2019", "$($Prefix)Contoso-Client", "$($Prefix)Contoso-Office") }
        SP2019WithOfficeMail { return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-SP2019", "$($Prefix)Contoso-Office", "$($Prefix)Contoso-Mail") }
        all {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-Client", "$($Prefix)Contoso-SP2019", "$($Prefix)Contoso-SP2016", "$($Prefix)Contoso-SP2013", "$($Prefix)Contoso-Office", "$($Prefix)Contoso-Mail")}
        Default {return @( "$($Prefix)Contoso-AD", "$($Prefix)Contoso-SQL")}
    }
    
}

function Get-VMDStopSequence 
{
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
        [string]
        $AzureResourceGroup,
        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
        [string]
        $HyperVPrefix                
    )
    if ($AzureResourceGroup) { $Prefix = $AzureResourceGroup.substring(0,$AzureResourceGroup.LastIndexOf('-') +1)}
    if ($HyperVPrefix) {$Prefix = "$($HyperVPrefix)-"}
    return @( "$($Prefix)Contoso-Mail", "$($Prefix)Contoso-SP2016", "$($Prefix)Contoso-SP2013", "$($Prefix)Contoso-Office","$($Prefix)Contoso-SP2019","$($Prefix)Contoso-Client", "$($Prefix)Contoso-SQL", "$($Prefix)Contoso-AD")
}

function Get-VMDStatus
{
    [CmdletBinding(DefaultParameterSetName="Azure")]    
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')]
        [string]
        $AzureResourceGroup,
        [Parameter(Mandatory = $false, ParameterSetName = 'HyperV')]
        [string]
        $HyperVPrefix          
    )
    If ((!$AzureResourceGroup) -and (!$HyperVPrefix))
    {
        $AzureResourceGroup = Select-VMDResourceGroup
    }
    If (!$HyperVPrefix)
    {    
        $AzureVMs = get-azurermvm -ResourceGroupName $AzureResourceGroup
        foreach ($AzureVM in $AzureVMs)
        { 
            $AzureVMStatus = Get-AzureRmVM -ResourceGroupName $AzureResourceGroup -Status -Name $AzureVM.Name
            Write-Host 'VM     ' $AzureVM.Name
            foreach ($VMStatus in $AzureVMStatus.Statuses)
            { 
                if($VMStatus.Code -match "PowerState/")
                {
                    Write-Host 'Status ' $VMStatus.Code 
                }
            }
            Write-Host '---------------------'
        }
    } else {
        #ToDo check HyperV VM status
    }
    
}

function Get-VMDResourceGroup
{
    param (
        
    )
    Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -match 'Contoso'}
}

function Select-VMDResourceGroup
{
    param (
        
    )
    $RGs = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -match 'Contoso'}
    if ($RGs)
    {
        $i = 1
        foreach ($RG in $RGs)
        {
            Write-host $i '    ' $RG.ResourceGroupName
            $i++
        }
        $choice = Read-Host -Prompt 'Please select your Resource Group'
        Write-Host 'Selected ' $RGs[($choice -1)].ResourceGroupName -ForegroundColor Green
        return $RGs[$choice -1].ResourceGroupName
    } else {
        Write-Host 'No VMD Resource Groups found' -ForegroundColor Yellow
        return $RGs
    }
    
}

function Select-VMDScenario
{
    param (
        
    )
    $Scenarios = @('SQLonly','SQLandClient','SP2013UseCases','SP2013WithOfficeOnline','SP2013WithOfficeMail','SP2016UseCases','SP2016WithOfficeOnline','SP2016WithOfficeMail','SP2019UseCases','SP2019WithOfficeOnline','SP2019WithOfficeMail','All')
    $i = 1
    foreach ($Scenario in $Scenarios)
    {
        Write-host $i '    ' $Scenario
        $i++
    }
    $choice = Read-Host -Prompt 'Please select your Scenario'
    Write-Host 'Selected ' $Scenarios[($choice -1)] -ForegroundColor Green
    return $Scenarios[$choice -1]
}

function New-VMDHyperV
{
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({test-path $_})]
        [string]
        $Path,
        [Parameter(Mandatory=$true)]
        $Prefix,
        [Parameter(Mandatory=$false)]
        [switch]
        $ConfigureMinimumRAM,
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]
        $VirtualMachinePartialName,
        [Parameter(Mandatory=$false)]
        [string]
        $HyperVHostIP,
        [Parameter(Mandatory=$false)]
        [switch]
        $UseDifferencingDisks,
        [Parameter(Mandatory=$false)]        
        [string]
        [ValidateScript({Test-Path $_})]
        $DifferencingVHDPath
    )
    import-module hyper-v -ErrorAction Stop
    
    #Create network, check first if its already exist
    if (!(get-vmswitch -name ("$($Prefix)-VMD-Internal") -ErrorAction SilentlyContinue))
    {
        Write-Host 'Create Hyper-V Switch and set host IP - one time task'
        New-VMSwitch  -Name ("$($Prefix)-VMD-Internal") -SwitchType Internal | Out-Null
        $VMAdapterIndex = (Get-NetAdapter "vEthernet ($($Prefix)-VMD-Internal)").InterfaceIndex
        New-NetIPAddress -IPAddress $HyperVHostIP -InterfaceIndex $VMAdapterIndex -AddressFamily IPv4 -PrefixLength 24 | Out-Null
    }
    
    #Get HyperV VHD root folder
    $HyperVRootVHDPath = Join-Path -Path (get-vmhost).virtualharddiskpath -ChildPath $Prefix
    #Create subfolder to put differencing disks in
    If ((!(Test-Path $HyperVRootVHDPath)) -and $UseDifferencingDisks)
    {
        mkdir $HyperVRootVHDPath
    }
    # In case vhds shouln't be stored in default HyperV directory
    If ($DifferencingVHDPath)
    {
        #Overwrite variable
        $HyperVRootVHDPath = $DifferencingVHDPath
    }

    switch ($VirtualMachinePartialName){
        AD {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-AD") -MemoryStartupBytes 1024MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-AD") -MemoryStartupBytes 768MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-AD") -processorcount 2 -AutomaticStartDelay 300 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save

                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-AD201615161334.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-AD-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-AD") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-AD-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-AD") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-AD201615161334.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-ad") -SwitchName "$($Prefix)-VMD-Internal"
                
                Enable-VMIntegrationService -VMName ("$($Prefix)-contoso-ad") -Name "Guest Service Interface"
            }
        SQL {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-SQL") -MemoryStartupBytes 8096MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-SQL") -MemoryStartupBytes 7168MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-SQL") -processorcount 4 -AutomaticStartDelay 420 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SQL201615163329.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-differencing.vhd")
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SQL-data1.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data1-differencing.vhd")
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SQL-data2.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data2-differencing.vhd")
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SQL-data3.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data3-differencing.vhd")
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SQL-data4.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data4-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data1-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data2-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data3-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SQL-data4-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-SQL201615163329.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $Path -ChildPath "Contoso-SQL-data1.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $Path -ChildPath "Contoso-SQL-data2.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $Path -ChildPath "Contoso-SQL-data3.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SQL") -ControllerType SCSI -ControllerNumber 0 -Path (Join-Path -Path $Path -ChildPath "Contoso-SQL-data4.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-sql") -SwitchName "$($Prefix)-VMD-Internal"
            }
        SP2013 {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-SP2013") -MemoryStartupBytes 14336MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-SP2013") -MemoryStartupBytes 12288MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-SP2013") -processorcount 4 -AutomaticStartDelay 720 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SP2013201618131334.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2013-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2013") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2013-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2013") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-SP2013201618131334.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-SP2013") -SwitchName "$($Prefix)-VMD-Internal"
               }
        SP2016 {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-SP2016") -MemoryStartupBytes 14336MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-SP2016") -MemoryStartupBytes 12288MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-SP2016") -processorcount 4 -AutomaticStartDelay 600 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SP2016201622215411.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2016-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2016") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2016-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2016") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-SP2016201622215411.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-SP2016") -SwitchName "$($Prefix)-VMD-Internal"
                }
        SP2016 {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-SP2016") -MemoryStartupBytes 14336MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-SP2016") -MemoryStartupBytes 12288MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-SP2016") -processorcount 4 -AutomaticStartDelay 600 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SP2016201622215411.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2016-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2016") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2016-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2016") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-SP2016201622215411.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-SP2016") -SwitchName "$($Prefix)-VMD-Internal"
                }
        SP2019 {
            If (!$ConfigureMinimumRAM)
            {
                new-vm -Name ("$($Prefix)-Contoso-SP2019") -MemoryStartupBytes 14336MB -Generation 1 -BootDevice IDE -NoVHD
            } else {
                new-vm -Name ("$($Prefix)-Contoso-SP2019") -MemoryStartupBytes 12288MB -Generation 1 -BootDevice IDE -NoVHD
            }
            set-vm -name ("$($Prefix)-Contoso-SP2019") -processorcount 4 -AutomaticStartDelay 600 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
            If ($UseDifferencingDisks)
            {
                New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-SP201920181023114007.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2019-differencing.vhd")
                Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2019") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-SP2019-differencing.vhd")
            } else {
                Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-SP2019") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-SP201920181023114007.vhd")
            }
            Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-SP2019") -SwitchName "$($Prefix)-VMD-Internal"
            }                                
        Office {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-Office") -MemoryStartupBytes 4096MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-Office") -MemoryStartupBytes 3072MB -Generation 1 -BootDevice IDE -NoVHD
                }
                
                set-vm -name ("$($Prefix)-Contoso-Office") -processorcount 2 -AutomaticStartDelay 900 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-Office2016822162630.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Office-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Office") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Office-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Office") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-Office2016822162630.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-Office") -SwitchName "$($Prefix)-VMD-Internal"
                }
        Mail {
                If (!$ConfigureMinimumRAM)
                {
                    new-vm -Name ("$($Prefix)-Contoso-Mail") -MemoryStartupBytes 8192MB -Generation 1 -BootDevice IDE -NoVHD
                } else {
                    new-vm -Name ("$($Prefix)-Contoso-Mail") -MemoryStartupBytes 6144MB -Generation 1 -BootDevice IDE -NoVHD
                }
                set-vm -name ("$($Prefix)-Contoso-Mail") -processorcount 2 -AutomaticStartDelay 1200 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
                If ($UseDifferencingDisks)
                {
                    New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "Contoso-Mail20170425162213.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Mail-differencing.vhd")
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Mail") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Mail-differencing.vhd")
                } else {
                    Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Mail") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "Contoso-Mail20170425162213.vhd")
                }
                Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-Mail") -SwitchName "$($Prefix)-VMD-Internal"            
            }
        Client {
            If (!$ConfigureMinimumRAM)
            {
                new-vm -Name ("$($Prefix)-Contoso-Client") -MemoryStartupBytes 4096MB -Generation 1 -BootDevice IDE -NoVHD
            } else {
                new-vm -Name ("$($Prefix)-Contoso-Client") -MemoryStartupBytes 2048MB -Generation 1 -BootDevice IDE -NoVHD
            }
            set-vm -name ("$($Prefix)-Contoso-Client") -processorcount 4 -AutomaticStartDelay 600 -AutomaticStartAction StartIfRunning -AutomaticStopAction Save
            If ($UseDifferencingDisks)
            {
                New-VHD -Differencing -ParentPath (Join-Path -Path $Path -ChildPath "DNS8-Contoso-CL20180517145702.vhd") -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Client-differencing.vhd")
                Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Client") -ControllerType IDE -Path (Join-Path -Path $HyperVRootVHDPath -ChildPath "Contoso-Client-differencing.vhd")
            } else {
                Add-VMHardDiskDrive -VMName ("$($Prefix)-Contoso-Client") -ControllerType IDE -Path (Join-Path -Path $Path -ChildPath "DNS8-Contoso-CL20180517145702.vhd")
            }
            Connect-VMNetworkAdapter -VMName ("$($Prefix)-contoso-Client") -SwitchName "$($Prefix)-VMD-Internal"
            }              
        Default {
            Write-Host 'No VM selected'
                }
    }

    return $Error
}


Function Set-VMNetworkConfiguration {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,
                   Position=1,
                   ParameterSetName='DHCP',
                   ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName='Static',
                   ValueFromPipeline=$true)]
        [Microsoft.HyperV.PowerShell.VMNetworkAdapter]$NetworkAdapter,

        [Parameter(Mandatory=$true,
                   Position=1,
                   ParameterSetName='Static')]
        [String[]]$IPAddress=@(),

        [Parameter(Mandatory=$false,
                   Position=2,
                   ParameterSetName='Static')]
        [String[]]$Subnet=@(),

        [Parameter(Mandatory=$false,
                   Position=3,
                   ParameterSetName='Static')]
        [String[]]$DefaultGateway = @(),

        [Parameter(Mandatory=$false,
                   Position=4,
                   ParameterSetName='Static')]
        [String[]]$DNSServer = @(),

        [Parameter(Mandatory=$false,
                   Position=0,
                   ParameterSetName='DHCP')]
        [Switch]$Dhcp
    )
    # Source: http://www.ravichaganti.com/blog/set-or-inject-guest-network-configuration-from-hyper-v-host-windows-server-2012/

    $VM = Get-WmiObject -Namespace 'root\virtualization\v2' -Class 'Msvm_ComputerSystem' | Where-Object { $_.ElementName -eq $NetworkAdapter.VMName } 
    $VMSettings = $vm.GetRelated('Msvm_VirtualSystemSettingData') | Where-Object { $_.VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized' }    
    $VMNetAdapters = $VMSettings.GetRelated('Msvm_SyntheticEthernetPortSettingData') 

    $NetworkSettings = @()
    foreach ($NetAdapter in $VMNetAdapters) {
        if ($NetAdapter.Address -eq $NetworkAdapter.MacAddress) {
            $NetworkSettings = $NetworkSettings + $NetAdapter.GetRelated("Msvm_GuestNetworkAdapterConfiguration")
        }
    }

    $NetworkSettings[0].IPAddresses = $IPAddress
    $NetworkSettings[0].Subnets = $Subnet
    $NetworkSettings[0].DefaultGateways = $DefaultGateway
    $NetworkSettings[0].DNSServers = $DNSServer
    $NetworkSettings[0].ProtocolIFType = 4096

    if ($dhcp) {
        $NetworkSettings[0].DHCPEnabled = $true
    } else {
        $NetworkSettings[0].DHCPEnabled = $false
    }

    $Service = Get-WmiObject -Class "Msvm_VirtualSystemManagementService" -Namespace "root\virtualization\v2"
    $setIP = $Service.SetGuestNetworkAdapterConfiguration($VM, $NetworkSettings[0].GetText(1))

    if ($setip.ReturnValue -eq 4096) {
        $job=[WMI]$setip.job 

        while ($job.JobState -eq 3 -or $job.JobState -eq 4) {
            start-sleep 1
            $job=[WMI]$setip.job
        }

        if ($job.JobState -eq 7) {
            write-host "Success"
        }
        else {
            $job.GetError()
        }
    } elseif($setip.ReturnValue -eq 0) {
        Write-Host "Success"
    }
}        


function Set-PageFile
{
    [CmdletBinding(SupportsShouldProcess=$True)]
    param (
            [Parameter(Mandatory=$true,Position=0)]
            [ValidateNotNullOrEmpty()]
            [String]
        $Path,
            [Parameter(Mandatory=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [Int]
        $InitialSize,
            [Parameter(Mandatory=$true,Position=2)]
            [ValidateNotNullOrEmpty()]
            [Int]
        $MaximumSize,
            [Parameter(Mandatory=$true,Position=3)]
            [ValidateNotNullOrEmpty()]
            [string]
        $Computer,
            [Parameter(Mandatory=$true,Position=4)]
            [System.Management.Automation.PSCredential]
            #[System.Management.Automation.CredentialAttribute()]
            #[SecureString] 
        $Credentials
    )
    <#
    .SYNOPSIS
        Sets Page File to custom size

    .DESCRIPTION
        Applies the given values for initial and maximum page file size.

    .PARAMETER Path
        The page file's fully qualified file name (such as C:\pagefile.sys)

    .PARAMETER InitialSize
        The page file's initial size [MB]

    .PARAMETER MaximumSize
        The page file's maximum size [MB]

    .EXAMPLE
        Set-PageFile C:\pagefile.sys 4096 6144
    #>
    Set-PSDebug -Strict

    $ComputerSystem = $null
    $CurrentPageFile = $null
    $Modified = $false

    # Disables automatically managed page file setting first
    try {
        $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges -ComputerName $Computer -Credential $Credentials
    }
    catch {
        Write-Host 'RPC call failed, maybe VM not ready yet. Wait 5 more minutes and try again'
        Start-Sleep -Seconds 500
        $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem -EnableAllPrivileges -ComputerName $Computer -Credential $Credentials
    }
    
    if ($ComputerSystem.AutomaticManagedPagefile)
    {
        $ComputerSystem.AutomaticManagedPagefile = $false
        if ($PSCmdlet.ShouldProcess("$($ComputerSystem.Path.Server)", 'Disable automatic managed page file'))
        {
            $ComputerSystem.Put()
        }
    }

    $CurrentPageFile = Get-WmiObject -Class Win32_PageFileSetting -ComputerName $Computer -Credential $Credentials
    if ($CurrentPageFile -ne $null) #Just continue if previous command did succeed
    {
        if ($CurrentPageFile.Name -eq $Path)
        {
            # Keeps the existing page file
            if ($CurrentPageFile.InitialSize -ne $InitialSize)
            {
                $CurrentPageFile.InitialSize = $InitialSize
                $Modified = $true
            }
            if ($CurrentPageFile.MaximumSize -ne $MaximumSize)
            {
                $CurrentPageFile.MaximumSize = $MaximumSize
                $Modified = $true
            }
            if ($Modified)
            {
                if ($PSCmdlet.ShouldProcess("Page file $Path", "Set initial size to $InitialSize and maximum size to $MaximumSize"))
                {
                    $CurrentPageFile.Put()
                }
            }
        }
        else
        {
            # Creates a new page file
            if ($PSCmdlet.ShouldProcess("Page file $($CurrentPageFile.Name)", 'Delete old page file'))
            {
                $CurrentPageFile.Delete()
            }
            if ($PSCmdlet.ShouldProcess("Page file $Path", "Set initial size to $InitialSize and maximum size to $MaximumSize"))
            {
                Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name=$Path; InitialSize = $InitialSize; MaximumSize = $MaximumSize} -ComputerName $Computer -Credential $Credentials
            }
        }
    }
}

Write-Debug 'VMDFunctions exit'