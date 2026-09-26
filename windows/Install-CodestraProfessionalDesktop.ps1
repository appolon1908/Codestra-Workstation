param(
    [Parameter(Mandatory=$true)][string]$ProfilePath,
    [Parameter(Mandatory=$true)][string[]]$PhotoSources,
    [string]$UserName = (Split-Path $ProfilePath -Leaf)
)

$ErrorActionPreference = "Stop"
$wallpaperDir = Join-Path $ProfilePath "Pictures\Codestra-Wallpaper"
$binDir = Join-Path $ProfilePath "AppData\Local\Codestra\Workstation"
$socialDir = Join-Path $ProfilePath "Desktop\Social Apps"
$workDir = Join-Path $ProfilePath "Desktop\Codestra Work"
$notesDir = Join-Path $workDir "Notes"
$startSocial = Join-Path $ProfilePath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Social Apps"

foreach ($dir in @($wallpaperDir,$binDir,$socialDir,$workDir,$notesDir,$startSocial)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Copy-Item "$PSScriptRoot\Rotate-CodestraWallpaper.ps1" "$binDir\Rotate-CodestraWallpaper.ps1" -Force
Copy-Item "$PSScriptRoot\Apply-CodestraUserShell.ps1" "$binDir\Apply-CodestraUserShell.ps1" -Force

$config = @{
    version = 1
    photo_sources = @($PhotoSources)
    exclude_patterns = @("Screenshots","Capturas de pantalla","Codestra-Wallpaper","\.cache")
    interval_minutes = 15
    image_fraction = 0.70
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 "$wallpaperDir\config.json"

$edge = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Microsoft Edge is required for app-mode social shortcuts" }

$apps = [ordered]@{
    "WhatsApp"="https://web.whatsapp.com/"; "Facebook"="https://www.facebook.com/";
    "Messenger"="https://www.messenger.com/"; "Instagram"="https://www.instagram.com/";
    "Threads"="https://www.threads.net/"; "X"="https://x.com/";
    "TikTok"="https://www.tiktok.com/"; "YouTube"="https://www.youtube.com/";
    "LinkedIn"="https://www.linkedin.com/"; "Telegram"="https://web.telegram.org/";
    "Snapchat"="https://web.snapchat.com/"; "Pinterest"="https://www.pinterest.com/";
    "Reddit"="https://www.reddit.com/"; "Discord"="https://discord.com/app"
}

$ws = New-Object -ComObject WScript.Shell
foreach ($name in $apps.Keys) {
    foreach ($folder in @($socialDir,$startSocial)) {
        $shortcut = $ws.CreateShortcut((Join-Path $folder "$name.lnk"))
        $shortcut.TargetPath = $edge
        $shortcut.Arguments = "--app=$($apps[$name]) --start-maximized"
        $shortcut.WorkingDirectory = Split-Path $edge
        $shortcut.IconLocation = "$edge,0"
        $shortcut.Description = "$name - Codestra Social Apps"
        $shortcut.Save()
    }
}

Get-ChildItem $socialDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "GIVE THIS TO CLAUDE OR COPILOT*" } |
    Move-Item -Destination $notesDir -Force

$canonical = @($apps.Keys)
$extras = Get-ChildItem $socialDir -Filter *.lnk -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -notin $canonical }
if ($extras) {
    $existing = Join-Path $socialDir "Existing"
    New-Item -ItemType Directory -Force -Path $existing | Out-Null
    foreach ($extra in $extras) {
        Move-Item $extra.FullName (Join-Path $existing $extra.Name) -Force
    }
}

$rotate = "$binDir\Rotate-CodestraWallpaper.ps1"
$apply = "$binDir\Apply-CodestraUserShell.ps1"
$principal = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Limited
$taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

$rotateAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$rotate+'"')
$rotateLogon = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$rotateRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName "Codestra Wallpaper Rotation" -Action $rotateAction -Trigger @($rotateLogon,$rotateRepeat) -Principal $principal -Settings $taskSettings -Force | Out-Null

$applyAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$apply+'"')
$applyLogon = New-ScheduledTaskTrigger -AtLogOn -User $UserName
Register-ScheduledTask -TaskName "Codestra Professional Desktop" -Action $applyAction -Trigger $applyLogon -Principal $principal -Settings $taskSettings -Force | Out-Null

powercfg /change monitor-timeout-ac 1440 | Out-Null
powercfg /change monitor-timeout-dc 1440 | Out-Null
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change standby-timeout-dc 0 | Out-Null

Start-ScheduledTask -TaskName "Codestra Professional Desktop"
Start-ScheduledTask -TaskName "Codestra Wallpaper Rotation"

Write-Output "CODESTRA_WORKSTATION_INSTALL=PASS"
Write-Output "PROFILE=$ProfilePath"
Write-Output "USER=$UserName"
Write-Output "SOCIAL_APPS=$($apps.Count)"
Write-Output "PHOTO_SOURCES=$($PhotoSources.Count)"
