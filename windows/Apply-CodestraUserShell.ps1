param()

$ErrorActionPreference = "Stop"
$root = Join-Path $env:LOCALAPPDATA "Codestra\Workstation"
$log = Join-Path $root "apply-shell.log"
$state = Join-Path $root "shell-state.json"
New-Item -ItemType Directory -Force -Path $root | Out-Null

try {
    "START $(Get-Date -Format o) $(whoami)" | Set-Content -Encoding UTF8 $log

    function Set-Dword([string]$Path, [string]$Name, [int]$Value) {
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            Set-ItemProperty -Path $Path -Name $Name -Type DWord -Value $Value
            "SET DWORD $Name=$Value" | Add-Content $log
        }
        catch {
            "SKIP DWORD $Name : $($_.Exception.Message)" | Add-Content $log
        }
    }
    function Set-String([string]$Path, [string]$Name, [string]$Value) {
        try {
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            Set-ItemProperty -Path $Path -Name $Name -Value $Value
            "SET STRING $Name=$Value" | Add-Content $log
        }
        catch {
            "SKIP STRING $Name : $($_.Exception.Message)" | Add-Content $log
        }
    }
    $personalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-Dword $personalize "AppsUseLightTheme" 0
    Set-Dword $personalize "SystemUsesLightTheme" 0
    Set-Dword $personalize "EnableTransparency" 1

    $advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-Dword $advanced "TaskbarAl" 1
    Set-Dword $advanced "ShowTaskViewButton" 0
    Set-Dword $advanced "TaskbarDa" 0
    Set-Dword $advanced "TaskbarMn" 0
    Set-Dword $advanced "ShowCopilotButton" 0
    Set-Dword $advanced "HideFileExt" 0
    Set-Dword $advanced "UseCompactMode" 1
    Set-Dword $advanced "LaunchTo" 1

    $search = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    Set-Dword $search "SearchboxTaskbarMode" 0

    $desktop = "HKCU:\Control Panel\Desktop"
    Set-String $desktop "ScreenSaveActive" "1"
    Set-String $desktop "ScreenSaveTimeOut" "86400"
    Set-String $desktop "ScreenSaverIsSecure" "1"
    Set-String $desktop "WallpaperStyle" "0"
    Set-String $desktop "TileWallpaper" "0"

    $p = Get-ItemProperty $personalize
    $a = Get-ItemProperty $advanced
    $s = Get-ItemProperty $search
    $d = Get-ItemProperty $desktop
    if ($p.AppsUseLightTheme -ne 0 -or $p.SystemUsesLightTheme -ne 0) {
        throw "required dark-theme settings were not applied"
    }
    if ($a.TaskbarAl -ne 1) {
        throw "required centered-taskbar setting was not applied"
    }
    if ($d.ScreenSaveActive -ne "1" -or $d.ScreenSaverIsSecure -ne "1" -or $d.ScreenSaveTimeOut -ne "86400") {
        throw "required 24-hour secure-lock settings were not applied"
    }
    [ordered]@{
        user = (whoami)
        applied_at = (Get-Date).ToString("o")
        dark_apps = $p.AppsUseLightTheme
        dark_system = $p.SystemUsesLightTheme
        transparency = $p.EnableTransparency
        taskbar_centered = $a.TaskbarAl
        task_view_hidden = $a.ShowTaskViewButton
        widgets_hidden = $a.TaskbarDa
        chat_hidden = $a.TaskbarMn
        copilot_hidden = $a.ShowCopilotButton
        file_extensions_visible = $a.HideFileExt
        compact_explorer = $a.UseCompactMode
        explorer_launch_to = $a.LaunchTo
        search_hidden = $s.SearchboxTaskbarMode
        secure_lock = $d.ScreenSaverIsSecure
        idle_seconds = $d.ScreenSaveTimeOut
    } | ConvertTo-Json | Set-Content -Encoding UTF8 $state

    Start-Process rundll32.exe -ArgumentList "user32.dll,UpdatePerUserSystemParameters" -WindowStyle Hidden -ErrorAction SilentlyContinue
    "PASS" | Add-Content $log
    exit 0
}
catch {
    ("ERROR " + $_.Exception.Message) | Add-Content $log
    ($_ | Out-String) | Add-Content $log
    exit 1
}
