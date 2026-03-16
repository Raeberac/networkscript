$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Green"
$Global:LastScanTime = "N/A"
Clear-Host

$BaseDir = "$env:TEMP\NetworkMonitor"
if (!(Test-Path $BaseDir)) { New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null }

$ConfigFile = Join-Path $BaseDir "ipscan_config.txt"
$LogFile    = Join-Path $BaseDir "ping_monitor.log"

if (!(Test-Path $ConfigFile)) { "300" | Out-File -FilePath $ConfigFile }
if (!(Test-Path $LogFile)) { "$(Get-Date) : SYSTEM : Monitor Started" | Out-File -FilePath $LogFile }

$FailedCount = @{}
$AlertSent   = @{} 

# --- OPTIONAL EMAIL CONFIGURATION ---
$EnableEmail = $false 
$SMTPServer  = "smtp.gmail.com"
$SMTPPort    = 587
$EmailFrom   = "your-alerts@gmail.com"
$EmailTo     = "admin@company.com"
$Username    = "your-email@gmail.com"
$Password    = "your-app-password" 
# ------------------------------------

function Get-Config {
    try {
        $Data = Get-Content $ConfigFile -ErrorAction Stop
        $Interval = $Data[0]; $Targets = @()
        if ($Data.Count -gt 1) {
            $Data | Select-Object -Skip 1 | ForEach-Object {
                $split = $_ -split "\|"
                if ($split[0]) {
                    $pData = if ($split.Count -gt 2) { $split[2] } else { "NONE" }
                    $Targets += [PSCustomObject]@{ 
                        IP = $split[0]; Status = $split[1]; 
                        Ports = if ($pData -eq "NONE" -or [string]::IsNullOrWhiteSpace($pData)) { @() } else { $pData -split "," } 
                    }
                }
            }
        }
        return @($Interval, $Targets)
    } catch { return @(300, @()) }
}

function Save-Config($Interval, $TargetObjects) {
    $Output = @($Interval)
    foreach ($Obj in $TargetObjects) { 
        $pString = if ($Obj.Ports.Count -gt 0) { ($Obj.Ports | Where-Object { $_ -match "^\d+$" }) -join "," } else { "NONE" }
        if ([string]::IsNullOrWhiteSpace($pString)) { $pString = "NONE" }
        $Output += "$($Obj.IP)|$($Obj.Status)|$pString" 
    }
    $Output | Out-File -FilePath $ConfigFile
}

function Send-AlertEmail($IP, $Detail) {
    if ($EnableEmail) {
        try {
            $SecPass = ConvertTo-SecureString $Password -AsPlainText -Force
            $Creds = New-Object System.Management.Automation.PSCredential($Username, $SecPass)
            Send-MailMessage -From $EmailFrom -To $EmailTo -Subject "NODE DOWN: $IP" -Body "CRITICAL: Node $IP unresponsive ($Detail) at $(Get-Date)." -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl -Credential $Creds
        } catch { "$(Get-Date) : ERR : Email Failure" | Out-File -FilePath $LogFile -Append }
    }
}

function Get-InputWithEsc {
    param([string]$Prompt)
    Write-Host " $Prompt" -NoNewline -ForegroundColor Green
    $InputString = ""
    while ($true) {
        if ($Host.UI.RawUI.KeyAvailable) {
            $Key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($Key.VirtualKeyCode -eq 27) { return "ESC_KEY" }
            if ($Key.VirtualKeyCode -eq 13) { Write-Host ""; return $InputString }
            if ($Key.VirtualKeyCode -eq 8) {
                if ($InputString.Length -gt 0) {
                    $InputString = $InputString.SubString(0, $InputString.Length - 1)
                    Write-Host -Object "`b `b" -NoNewline
                }
            } else { $InputString += $Key.Character; Write-Host -Object $Key.Character -NoNewline }
        }
        Start-Sleep -Milliseconds 10
    }
}

function Write-Header {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host "  NETWORK ADDRESS MONITOR" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    $Config = Get-Config
    Write-Host "  LAST SCAN: $Global:LastScanTime | INTERVAL: $($Config[0])s" -ForegroundColor Cyan
    Write-Host "  STORAGE: $BaseDir" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------" -ForegroundColor Green
}

while ($true) {
    Write-Header
    Write-Host " [1] ADD IP ADDRESS" -ForegroundColor Green
    Write-Host " [2] REMOVE IP ADDRESS" -ForegroundColor Green
    Write-Host " [3] CONFIGURE TIMING" -ForegroundColor Green
    Write-Host " [4] START SCAN" -ForegroundColor Green
    Write-Host " [5] MAINTENANCE MODE" -ForegroundColor Yellow
    Write-Host " [6] EXIT" -ForegroundColor Red
    Write-Host ""
    $choice = Read-Host " > SYSTEM_INPUT"

    switch ($choice) {
        "1" {
            Write-Header
            Write-Host " [ACTION: ADD TARGET] (ESC to Cancel)" -ForegroundColor DarkGray
            $ip = Get-InputWithEsc -Prompt "> ENTER IP: "
            if ($ip -ne "ESC_KEY" -and $ip -match "^\d{1,3}(\.\d{1,3}){3}$") { 
                $ports = Get-InputWithEsc -Prompt "> PORTS (e.g., 80, 443, 21) OR BLANK: "
                $pFinal = if ($ports -eq "" -or $ports -eq "ESC_KEY") { "NONE" } else { $ports -replace " ", "" }
                "$ip|ACTIVE|$pFinal" | Out-File -FilePath $ConfigFile -Append 
                "$(Get-Date) : CONFIG : Added $ip" | Out-File -FilePath $LogFile -Append
                Write-Host " [+] TARGET ACQUIRED." -ForegroundColor Green; Start-Sleep -Seconds 1
            }
        }
        "2" {
            Write-Header
            $Config = Get-Config
            Write-Host " [ACTION: PURGE TARGETS] (ESC to Cancel)" -ForegroundColor DarkGray
            $Config[1] | ForEach-Object { Write-Host " - $($_.IP)" }
            Write-Host ""
            $val = Get-InputWithEsc -Prompt "> IP(S) TO REMOVE (e.g. 1.1.1.1, 2.2.2.2): "
            if ($val -ne "ESC_KEY" -and ![string]::IsNullOrWhiteSpace($val)) {
                $PurgeList = $val -split "," | ForEach-Object { $_.Trim() }
                $InitialTargets = $Config[1]
                $RemainingTargets = $InitialTargets | Where-Object { $PurgeList -notcontains $_.IP }
                $DeletedCount = $InitialTargets.Count - $RemainingTargets.Count
                Save-Config -Interval $Config[0] -TargetObjects $RemainingTargets
                "$(Get-Date) : CONFIG : Purged $DeletedCount targets" | Out-File -FilePath $LogFile -Append
                Write-Host " [-] $DeletedCount TARGET(S) REMOVED FROM SYSTEM." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        }
        "4" {
            $StopScan = $false
            while (-not $StopScan) {
                Write-Header
                $Config = Get-Config
                if ($Config[1].Count -eq 0) {
                    Write-Host " [!] NO TARGETS FOUND." -ForegroundColor Red
                    Start-Sleep -Seconds 2; break
                }
                Write-Host " [!] MONITORING BEGUN... (ESC to Exit)`n" -ForegroundColor Green
                foreach ($T in $Config[1]) {
                    $Time = Get-Date -Format "HH:mm:ss"
                    $Up = $false; $Detail = "Ping"
                    if ($T.Ports.Count -gt 0) {
                        foreach ($P in $T.Ports) {
                            if ($P -match "^\d+$" -and [int]$P -gt 0) {
                                if (Test-NetConnection -ComputerName $T.IP -Port [int]$P -InformationLevel Quiet -WarningAction SilentlyContinue) {
                                    $Up = $true; $Detail = "Port $P"; break
                                }
                            }
                        }
                    } else { if (Test-Connection -ComputerName $T.IP -Count 2 -Quiet) { $Up = $true } }

                    if ($Up) {
                        $FailedCount[$T.IP] = 0; $AlertSent[$T.IP] = $false
                        Write-Host " [$Time] ONLINE  : $($T.IP) ($Detail)" -ForegroundColor Green
                    } else {
                        if ($T.Status -eq "ACTIVE") {
                            $FailedCount[$T.IP]++
                            "$(Get-Date) : FAIL : $($T.IP) ($Detail) - ATTEMPT $($FailedCount[$T.IP])" | Out-File -FilePath $LogFile -Append
                            Write-Host " [$Time] OFFLINE : $($T.IP) (FAIL: $($FailedCount[$T.IP]))" -ForegroundColor Red
                            if ($FailedCount[$T.IP] -ge 3 -and -not $AlertSent[$T.IP]) {
                                $AlertSent[$T.IP] = $true
                                Send-AlertEmail -IP $T.IP -Detail $Detail
                                "$(Get-Date) : CRITICAL : $($T.IP) DOWN ($Detail)" | Out-File -FilePath $LogFile -Append
                                (New-Object -ComObject Wscript.Shell).Popup("CRITICAL: $($T.IP) is down!", 0, "SYSTEM DOWN", 0x10)
                            }
                        } else { Write-Host " [$Time] OFFLINE : $($T.IP) (SNOOZED)" -ForegroundColor Yellow }
                    }
                }
                $Global:LastScanTime = Get-Date -Format "HH:mm:ss"
                Write-Host ""
                for ($i = [int]$Config[0]; $i -gt 0; $i--) {
                    if ($Host.UI.RawUI.KeyAvailable) {
                        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        if ($key.VirtualKeyCode -eq 27) { $StopScan = $true; break }
                    }
                    $msg = " [>] NEXT CYCLE IN $($i)s... (ESC to Exit) "
                    Write-Host -Object $msg -NoNewline -ForegroundColor DarkGray
                    Start-Sleep -Seconds 1; Write-Host -Object ("`b" * $msg.Length) -NoNewline
                }
            }
        }
        "5" {
            Write-Header
            $Config = Get-Config
            Write-Host " [ACTION: MAINTENANCE SNOOZING] (ESC to Cancel)" -ForegroundColor DarkGray
            foreach ($T in $Config[1]) {
                if ($T.Status -eq "SNOOZED") {
                    Write-Host " - $($T.IP) [SNOOZED]" -ForegroundColor Red
                } else {
                    Write-Host " - $($T.IP) [ACTIVE]" -ForegroundColor Green
                }
            }
            Write-Host ""
            $val = Get-InputWithEsc -Prompt "> IP(S) TO TOGGLE (e.g. 1.1.1.1, 2.2.2.2): "
            if ($val -ne "ESC_KEY" -and ![string]::IsNullOrWhiteSpace($val)) {
                $ToggleList = $val -split "," | ForEach-Object { $_.Trim() }
                $AffectedCount = 0
                foreach ($T in $Config[1]) {
                    if ($ToggleList -contains $T.IP) {
                        $T.Status = if ($T.Status -eq "ACTIVE") { "SNOOZED" } else { "ACTIVE" }
                        $AffectedCount++
                    }
                }
                Save-Config -Interval $Config[0] -TargetObjects $Config[1]
                "$(Get-Date) : CONFIG : Toggled maintenance for $AffectedCount targets" | Out-File -FilePath $LogFile -Append
                Write-Host " [*] $AffectedCount TARGETS UPDATED." -ForegroundColor Cyan; Start-Sleep -Seconds 1
            }
        }
        "3" {
            Write-Header
            Write-Host " [ACTION: UPDATE INTERVAL] (ESC to Cancel)" -ForegroundColor DarkGray
            $val = Get-InputWithEsc -Prompt "> INTERVAL (SEC): "
            if ($val -ne "ESC_KEY" -and $val -match "^\d+$") {
                $Config = Get-Config
                Save-Config -Interval $val -TargetObjects $Config[1]
                "$(Get-Date) : CONFIG : Interval changed to $val" | Out-File -FilePath $LogFile -Append
                Write-Host " [*] TIMING UPDATED." -ForegroundColor Green; Start-Sleep -Seconds 1
            }
        }
        "6" { exit }
    }
}
