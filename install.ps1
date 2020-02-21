Start-Transcript C:\module_installation.txt

Write-Output "Module Path"
$Env:PSModulePath

Write-Output "Installing PackageProvider"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Write-Output "Setting PSRepository"
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

Write-Output "Installing Modules"
Install-Module xActiveDirectory, xComputerManagement, xNetworking, xAdcsDeployment, xDnsServer, xSystemSecurity -confirm:$false -Scope AllUsers -Force

Stop-Transcript
