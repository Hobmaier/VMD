[xml]$XMLconfig = Get-Content $PSScriptRoot\Contoso-Config.xml

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