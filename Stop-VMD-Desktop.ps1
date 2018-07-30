$AzureSubscriptionID = 'ebe822aa-3676-434b-8f1f-dc4df4efb75f'
$ContosoResourceGroup = 'Christian-Contoso'
If (!(Get-Module VMD)) { Import-Module -Name VMD -ErrorAction Stop }
Connect-VMD -AzureSubscriptionID $AzureSubscriptionID
Stop-VMD -AzureResourceGroup $ContosoResourceGroup
Write-Host 'All done' -ForegroundColor Green
Start-Sleep -Seconds 5