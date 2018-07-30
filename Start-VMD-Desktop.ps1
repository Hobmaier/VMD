$AzureSubscriptionID = 'ebe822aa-3676-434b-8f1f-dc4df4efb75f'
$ContosoResourceGroup = 'Christian-Contoso'
Import-Module -Name VMD -ErrorAction Stop
Connect-VMD -AzureSubscriptionID $AzureSubscriptionID
Start-VMD -AzureResourceGroup $ContosoResourceGroup -Szenario SP2013UseCases
Write-Host "SQL RDP URL: s2s$($ContosoResourceGroup)sql.northeurope.cloudapp.azure.com"
Write-Host 'All done' -ForegroundColor Green
Start-Sleep -Seconds 5