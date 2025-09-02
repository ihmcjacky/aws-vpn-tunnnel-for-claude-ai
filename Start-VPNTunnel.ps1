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

# Function to stop all services
function Stop-AllServices {
    param($Config)

    Write-Host "`n=== Stopping All Services ===" -ForegroundColor Yellow

    # Stop SSH tunnel
    Write-Host "Stopping SSH tunnel..." -ForegroundColor Cyan
    try {
        $sshProcesses = Get-Process -Name "ssh" -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -eq "ssh"
        }

        foreach ($process in $sshProcesses) {
            try {
                $process.Kill()
                Write-Host "Stopped SSH process (PID: $($process.Id))" -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to stop SSH process (PID: $($process.Id)): $_" -ForegroundColor Red
            }
        }

        if (-not $sshProcesses) {
            Write-Host "No SSH processes found to stop" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "Error stopping SSH tunnel: $_" -ForegroundColor Red
    }

    # Stop Docker container
    Write-Host "Stopping Docker container..." -ForegroundColor Cyan
    try {
        $result = docker stop $Config.Docker.ContainerName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker container stopped successfully" -ForegroundColor Green
        } else {
            Write-Host "Docker container stop result: $result" -ForegroundColor Gray
        }

        # Remove container
        docker rm $Config.Docker.ContainerName -f 2>$null | Out-Null
    }
    catch {
        Write-Host "Error stopping Docker container: $_" -ForegroundColor Red
    }

    # Reset Windows proxy settings
    Write-Host "Resetting Windows proxy settings..." -ForegroundColor Cyan
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 0 -Force
        Set-ItemProperty -Path $regPath -Name "AutoConfigURL" -Value "" -Force
        Write-Host "Windows proxy settings reset" -ForegroundColor Green
    }
    catch {
        Write-Host "Error resetting Windows proxy settings: $_" -ForegroundColor Red
    }

    Write-Host "All services stopped" -ForegroundColor Green
}

# Function to monitor SSH connectivity logs
function Show-SSHConnectivityLogs {
    param($Config)

    Write-Host "`n=== SSH Connectivity Monitor ===" -ForegroundColor Cyan
    Write-Host "Monitoring SSH tunnel connections..." -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop monitoring and return to menu" -ForegroundColor Gray
    Write-Host ""

    try {
        # Monitor network connections on the SOCKS5 port
        while ($true) {
            $connections = Get-NetTCPConnection -LocalPort $Config.SSH.LocalPort -ErrorAction SilentlyContinue

            if ($connections) {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] Active connections on port $($Config.SSH.LocalPort):" -ForegroundColor Cyan

                foreach ($conn in $connections) {
                    $state = $conn.State
                    $remoteAddress = $conn.RemoteAddress
                    $remotePort = $conn.RemotePort

                    $color = switch ($state) {
                        "Established" { "Green" }
                        "Listen" { "Yellow" }
                        "TimeWait" { "Gray" }
                        default { "White" }
                    }

                    Write-Host "  $state`: $remoteAddress`:$remotePort" -ForegroundColor $color
                }
                Write-Host ""
            }

            Start-Sleep -Seconds 5
        }
    }
    catch {
        Write-Host "`nStopped monitoring SSH connectivity" -ForegroundColor Yellow
    }
}

# Function to show post-setup interactive menu
function Show-PostSetupMenu {
    param($Config)

    while ($true) {
        Write-Host "`n=== VPN Tunnel Management Menu ===" -ForegroundColor Magenta
        Write-Host "1. Monitor SSH connectivity logs" -ForegroundColor White
        Write-Host "2. Terminate all services and exit" -ForegroundColor White
        Write-Host "3. Exit (keep services running)" -ForegroundColor White
        Write-Host ""

        $choice = Read-Host "Select an option (1-3)"

        switch ($choice) {
            "1" {
                Show-SSHConnectivityLogs -Config $Config
            }
            "2" {
                Write-Host "`nTerminating all services..." -ForegroundColor Yellow
                Stop-AllServices -Config $Config
                Write-Host "`nAll services terminated. Exiting..." -ForegroundColor Green
                return $false
            }
            "3" {
                Write-Host "`nExiting while keeping services running..." -ForegroundColor Green
                Write-Host "Services will continue running in the background." -ForegroundColor Gray
                return $true
            }
            default {
                Write-Host "Invalid choice. Please select 1, 2, or 3." -ForegroundColor Red
            }
        }
    }
}

# Function to handle setup failure and ask for retry
function Handle-SetupFailure {
    param($Config)

    Write-Host "`n=== Setup Failed ===" -ForegroundColor Red
    Write-Host "Some steps failed during the VPN tunnel setup." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "1. Retry setup (will stop all services first)" -ForegroundColor White
    Write-Host "2. Exit without retry" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "Select an option (1-2)"

    switch ($choice) {
        "1" {
            Write-Host "`nPreparing for retry..." -ForegroundColor Yellow
            Stop-AllServices -Config $Config
            Start-Sleep -Seconds 3
            Write-Host "`nRetrying setup..." -ForegroundColor Cyan
            return $true
        }
        "2" {
            Write-Host "`nExiting without retry..." -ForegroundColor Gray
            return $false
        }
        default {
            Write-Host "Invalid choice. Exiting..." -ForegroundColor Red
            return $false
        }
    }
}

# Main execution with retry logic
Write-Host "AWS VPN Tunnel Setup" -ForegroundColor Magenta
Write-Host "===================" -ForegroundColor Magenta

do {
    $retrySetup = $false

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
        # All steps successful
        Write-Host "`nVPN Tunnel setup completed successfully!" -ForegroundColor Green
        Write-Host "You can now browse to geo-restricted sites like https://claude.ai" -ForegroundColor Cyan

        # Show post-setup interactive menu
        $keepServicesRunning = Show-PostSetupMenu -Config $config

        if ($keepServicesRunning) {
            Write-Host "`nServices are still running in the background." -ForegroundColor Green
            Write-Host "To stop them later, run this script again and choose 'Terminate all services'." -ForegroundColor Gray
        }

        break
    } else {
        # Some steps failed - ask for retry
        $retrySetup = Handle-SetupFailure -Config $config
    }

} while ($retrySetup)

Write-Host "`nScript execution completed." -ForegroundColor Magenta
