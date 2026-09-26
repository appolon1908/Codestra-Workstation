param(
    [Parameter(Mandatory=$true)][string]$ProfilePath
)

$ErrorActionPreference = "Stop"
$wallpaper = Join-Path $ProfilePath "Pictures\Codestra-Wallpaper\wallpaper.jpg"
$wallState = Join-Path $ProfilePath "Pictures\Codestra-Wallpaper\state.json"
$shellState = Join-Path $ProfilePath "AppData\Local\Codestra\Workstation\shell-state.json"
$social = Join-Path $ProfilePath "Desktop\Social Apps"

$result = [ordered]@{
    profile = $ProfilePath
    wallpaper_exists = (Test-Path $wallpaper)
    wallpaper_state_exists = (Test-Path $wallState)
    shell_state_exists = (Test-Path $shellState)
    social_shortcuts = @(Get-ChildItem $social -Filter *.lnk -ErrorAction SilentlyContinue).Count
    rotate_task = (Get-ScheduledTask -TaskName "Codestra Wallpaper Rotation" -ErrorAction SilentlyContinue).State
    shell_task = (Get-ScheduledTask -TaskName "Codestra Professional Desktop" -ErrorAction SilentlyContinue).State
    rotate_last_result = (Get-ScheduledTaskInfo -TaskName "Codestra Wallpaper Rotation" -ErrorAction SilentlyContinue).LastTaskResult
    shell_last_result = (Get-ScheduledTaskInfo -TaskName "Codestra Professional Desktop" -ErrorAction SilentlyContinue).LastTaskResult
}
if (Test-Path $wallState) {
    $wall = Get-Content $wallState -Raw | ConvertFrom-Json
    $result.selected_photo = $wall.selected
    $result.presentation = $wall.presentation
}
if (Test-Path $shellState) {
    $result.shell = Get-Content $shellState -Raw | ConvertFrom-Json
}
$result | ConvertTo-Json -Depth 6
