param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Assert-SourceSafety.ps1"
$text = Get-Content (Join-Path $RepositoryRoot 'windows/Rotate-CodestraWallpaper.ps1') -Raw
$ast = Assert-SourceSafety -Text $text -Label Rotate
$filters = @($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Where-Object' -and $n.Extent.Text.Contains('.Extension')}, $true))
if ($filters.Count -ne 1) { throw 'Photo filter inventory changed' }
$filter = $filters[0].CommandElements[1].ScriptBlock.GetScriptBlock()
$exclude = @('Screenshots','Capturas de pantalla','Codestra-Wallpaper','\.cache')
$files = @(
    [pscustomobject]@{FullName='C:\Fixture\Screenshots\first.png';Extension='.png'},
    [pscustomobject]@{FullName='C:\Fixture\Capturas de pantalla\second.jpg';Extension='.jpg'},
    [pscustomobject]@{FullName='C:\Fixture\Codestra-Wallpaper\wallpaper.jpg';Extension='.jpg'},
    [pscustomobject]@{FullName='C:\Fixture\.cache\cached.bmp';Extension='.bmp'},
    [pscustomobject]@{FullName='C:\Fixture\allowed.JPG';Extension='.JPG'},
    [pscustomobject]@{FullName='C:\Fixture\notes.txt';Extension='.txt'}
)
$selected = @($files | Where-Object $filter)
if ($selected.Count -ne 1 -or $selected[0].FullName -ne 'C:\Fixture\allowed.JPG') { throw "Excluded photo selected: $($selected.FullName -join ', ')" }
Write-Output 'PHOTO_EXCLUSION_REGRESSION=PASS'
