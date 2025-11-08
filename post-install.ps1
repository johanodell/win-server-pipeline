# Windows Server 2022 Post-Install Script
# Configures WinRM for Ansible and prepares system for sysprep

Write-Host "Starting post-install configuration..."

# Enable PSRemoting and configure WinRM for Ansible
Write-Host "Configuring WinRM..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Configure WinRM Service settings
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\Auth\CredSSP -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Configure WinRM Client settings (required for Ansible)
Set-Item WSMan:\localhost\Client\AllowUnencrypted -Value $true

# Configure firewall
Write-Host "Configuring firewall..."
New-NetFirewallRule -Name 'WinRM-HTTP' -DisplayName 'Windows Remote Management (HTTP-In)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue

# Set WinRM service to automatic
Write-Host "Setting WinRM service to automatic..."
Set-Service WinRM -StartupType Automatic
Restart-Service WinRM

# Set PowerShell execution policy
Write-Host "Setting PowerShell execution policy..."
Set-ExecutionPolicy RemoteSigned -Force

Write-Host "Post-install configuration completed successfully!"
