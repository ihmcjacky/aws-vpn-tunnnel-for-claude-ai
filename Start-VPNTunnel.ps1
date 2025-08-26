#Requires -Version 5.1

param()

# Configuration file path
$ConfigFile = Join-Path $PSScriptRoot "config.ini"

# Function to read INI file
function Read-IniFile {
    param([string]$FilePath)
    
    $ini = @{}
    $section = ""
    
    if (Test-Path $FilePath) {
        Get-Content $FilePath | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\[(.+)\]$') {
                $section = $matches[1]
                $ini[$section] = @{}
            }
            elseif ($line -match '^(.+?)=(.*)$' -and $section) {
                $ini[$section][$matches[1]] = $matches[2]
            }
        }
    }
    return $ini
}

# Function to get configuration with interactive prompts
function Get-Configuration {
    Write-Host "=== AWS VPN Tunnel Configuration ===" -ForegroundColor Cyan
    
    # Read existing config
    $config = Read-IniFile -FilePath $ConfigFile
    
    # SSH Configuration
    if (-not $config.SSH) { $config.SSH = @{} }
    
    $keyPath = $config.SSH.KeyPath
    if (-not $keyPath -or -not (Test-Path $keyPath)) {
        $keyPath = Read-Host "Enter SSH private key path [C:\Users\your-username\Documents\Appz\PAC-Server\your-key.pem]"
        if (-not $keyPath) { $keyPath = "C:\Users\your-username\Documents\Appz\PAC-Server\your-key.pem" }
    }
    
    $username = $config.SSH.Username
    if (-not $username) {
        $username = Read-Host "Enter SSH username [your-ssh-username]"
        if (-not $username) { $username = "your-ssh-username" }
    }
    
    $hostname = $config.SSH.Hostname
    if (-not $hostname) {
        $hostname = Read-Host "Enter SSH hostname [your-lightsail-instance.com]"
        if (-not $hostname) { $hostname = "your-lightsail-instance.com" }
    }
    
    $localPort = $config.SSH.LocalPort
    if (-not $localPort) {
        $localPort = Read-Host "Enter local SOCKS5 port [1080]"
        if (-not $localPort) { $localPort = "1080" }
    }
    
    # Docker Configuration
    if (-not $config.Docker) { $config.Docker = @{} }
    
    $pacFilePath = $config.Docker.PACFilePath
    if (-not $pacFilePath -or -not (Test-Path $pacFilePath.Replace('/', '\'))) {
        $pacFilePath = Read-Host "Enter PAC file path [C:/Users/your-username/Documents/Appz/PAC-Server/proxy.pac]"
        if (-not $pacFilePath) { $pacFilePath = "C:/Users/your-username/Documents/Appz/PAC-Server/proxy.pac" }
    }
    
    $containerName = $config.Docker.ContainerName
    if (-not $containerName) { $containerName = "PAC" }
    
    $port = $config.Docker.Port
    if (-not $port) { $port = "8080" }
    
    # Return configuration object
    return @{
        SSH = @{
            KeyPath = $keyPath
            Username = $username
            Hostname = $hostname
            LocalPort = $localPort
        }
        Docker = @{
            PACFilePath = $pacFilePath
            ContainerName = $containerName
            Port = $port
        }
        Proxy = @{
            ScriptURL = "http://127.0.0.1:$port/proxy.pac"
        }
    }
}

# Function to start Docker container
function Start-DockerContainer {
    param($Config)
    
    Write-Host "`n=== Step 1: Starting Docker Container ===" -ForegroundColor Yellow
    
    # Check if container is already running
    $running = docker ps --filter "name=$($Config.Docker.ContainerName)" --format '{{.Names}}' 2>$null
    if ($running -eq $Config.Docker.ContainerName) {
        Write-Host "Docker container is already running" -ForegroundColor Green
        return $true
    }
    
    # Check if PAC file exists
    $pacPath = $Config.Docker.PACFilePath.Replace('/', '\')
    if (-not (Test-Path $pacPath)) {
        Write-Host "PAC file not found: $pacPath" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Starting Docker container..." -ForegroundColor Cyan
    
    try {
        # Remove existing container if it exists but is stopped
        docker rm $Config.Docker.ContainerName -f 2>$null | Out-Null
        
        # Start new container
        $result = docker run -it -d -p "$($Config.Docker.Port):80" -v "$($Config.Docker.PACFilePath):/usr/share/nginx/html/proxy.pac" --name $Config.Docker.ContainerName nginx 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker container started successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to start Docker container: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error starting Docker container: $_" -ForegroundColor Red
        return $false
    }
}

# Function to start SSH tunnel
function Start-SSHTunnel {
    param($Config)
    
    Write-Host "`n=== Step 2: Starting SSH Tunnel ===" -ForegroundColor Yellow
    
    # Check if SSH tunnel is already running
    $existing = Get-NetTCPConnection -LocalPort $Config.SSH.LocalPort -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "SSH tunnel is already running on port $($Config.SSH.LocalPort)" -ForegroundColor Green
        return $true
    }
    
    # Check if SSH key exists
    if (-not (Test-Path $Config.SSH.KeyPath)) {
        Write-Host "SSH key file not found: $($Config.SSH.KeyPath)" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Starting SSH tunnel..." -ForegroundColor Cyan
    $sshCommand = "ssh -i `"$($Config.SSH.KeyPath)`" -v -N -D $($Config.SSH.LocalPort) $($Config.SSH.Username)@$($Config.SSH.Hostname)"
    Write-Host "Command: $sshCommand" -ForegroundColor Gray
    
    try {
        # Start SSH tunnel in background
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "ssh"
        $processInfo.Arguments = "-i `"$($Config.SSH.KeyPath)`" -v -N -D $($Config.SSH.LocalPort) $($Config.SSH.Username)@$($Config.SSH.Hostname)"
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        # Wait a moment and check if tunnel is active
        Start-Sleep -Seconds 3
        $tunnelActive = Get-NetTCPConnection -LocalPort $Config.SSH.LocalPort -State Listen -ErrorAction SilentlyContinue
        
        if ($tunnelActive) {
            Write-Host "SSH tunnel started successfully on port $($Config.SSH.LocalPort)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "SSH tunnel failed to start" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error starting SSH tunnel: $_" -ForegroundColor Red
        return $false
    }
}

# Function to configure Windows proxy settings
function Set-WindowsProxySettings {
    param($Config)
    
    Write-Host "`n=== Step 3: Configuring Windows Proxy Settings ===" -ForegroundColor Yellow
    
    try {
        # Registry path for proxy settings
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        
        Write-Host "Disabling proxy settings first..." -ForegroundColor Cyan
        
        # Step 1: Disable proxy settings first
        Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 0 -Force
        Set-ItemProperty -Path $regPath -Name "AutoConfigURL" -Value "" -Force
        
        Start-Sleep -Seconds 2
        
        Write-Host "Proxy settings disabled" -ForegroundColor Green
        
        Write-Host "Enabling proxy script..." -ForegroundColor Cyan
        
        # Step 2: Enable proxy script
        Set-ItemProperty -Path $regPath -Name "AutoConfigURL" -Value $Config.Proxy.ScriptURL -Force
        Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 0 -Force
        
        Write-Host "Windows proxy settings configured successfully" -ForegroundColor Green
        Write-Host "Script URL: $($Config.Proxy.ScriptURL)" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "Error configuring Windows proxy settings: $_" -ForegroundColor Red
        return $false
    }
}

# Main execution
Write-Host "AWS VPN Tunnel Setup" -ForegroundColor Magenta
Write-Host "===================" -ForegroundColor Magenta

# Get configuration
$config = Get-Configuration

# Execute the 3 steps
$step1 = Start-DockerContainer -Config $config
$step2 = Start-SSHTunnel -Config $config
$step3 = Set-WindowsProxySettings -Config $config

# Summary
Write-Host "`n=== Setup Summary ===" -ForegroundColor Magenta
if ($step1) { Write-Host "Docker Container: Running" -ForegroundColor Green } else { Write-Host "Docker Container: Failed" -ForegroundColor Red }
if ($step2) { Write-Host "SSH Tunnel: Active" -ForegroundColor Green } else { Write-Host "SSH Tunnel: Failed" -ForegroundColor Red }
if ($step3) { Write-Host "Windows Proxy: Configured" -ForegroundColor Green } else { Write-Host "Windows Proxy: Failed" -ForegroundColor Red }

if ($step1 -and $step2 -and $step3) {
    Write-Host "`nVPN Tunnel setup completed successfully!" -ForegroundColor Green
    Write-Host "You can now browse to geo-restricted sites like https://claude.ai" -ForegroundColor Cyan
} else {
    Write-Host "`nSome steps failed. Please check the errors above." -ForegroundColor Yellow
}

Write-Host "`nPress Enter to exit..."
Read-Host
