param([switch]$PortableOnly)
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/Assert-SourceSafety.ps1"
if(-not $PortableOnly -and -not $IsWindows){throw 'Full source behavior requires the hosted Windows test lane'}
$script:Assertions=0;$script:Cases=0
function Assert([bool]$Condition,[string]$Message){$script:Assertions++;if(-not $Condition){throw "ASSERTION_FAILED=$Message"}}
$pwsh=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$root=Join-Path ([IO.Path]::GetTempPath()) ('codestra-source-ci-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
function New-Fixture([string]$Name){
    $path=Join-Path $root $Name
    [IO.Directory]::CreateDirectory((Join-Path $path 'Profile/Desktop/Social Apps'))|Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $path 'Photos'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $path 'Profile/Desktop/unrelated.txt'),'preserve unrelated bytes')
    return $path
}
function Child([string]$Scenario,[string]$Fixture,[int]$ExpectedExit=0){
    $script:Cases++
    $output=& $pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/Invoke-MockedScenario.ps1" -RepositoryRoot $repository -FixtureRoot $Fixture -Scenario $Scenario 2>&1
    $code=$LASTEXITCODE
    Assert ($code -eq $ExpectedExit) "$Scenario exit $code expected $ExpectedExit : $output"
    $ledger=Get-Content (Join-Path $Fixture 'mock-ledger.json') -Raw|ConvertFrom-Json -AsHashtable
    Assert ($ledger.Preflight -eq $true) "$Scenario preflight not executed"
    Assert ((Get-Content (Join-Path $Fixture 'Profile/Desktop/unrelated.txt') -Raw) -eq 'preserve unrelated bytes') "$Scenario altered unrelated desktop bytes"
    return @{Ledger=$ledger;Output=($output -join "`n");Fixture=$Fixture}
}
function Assert-NoExternalEffects($Result){
    Assert ($Result.Ledger.NativeCalls.Count -eq 0) 'Unexpected wallpaper boundary invocation'
    Assert ($Result.Ledger.ScreenReads -eq 0) 'Unexpected screen boundary invocation'
}
function Photo-Fixture([string]$Name,[switch]$ExcludedOnly,[switch]$Bad){
    $fixture=New-Fixture $Name
    $folder=Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper';[IO.Directory]::CreateDirectory($folder)|Out-Null
    $photos=Join-Path $fixture 'Photos';[IO.Directory]::CreateDirectory((Join-Path $photos '00-Screenshots'))|Out-Null
    foreach($entry in @(@{File='00-Screenshots/excluded.png';Color=[Drawing.Color]::Lime},@{File='allowed-a.jpg';Color=[Drawing.Color]::Red},@{File='allowed-b.png';Color=[Drawing.Color]::Blue})){
        if($ExcludedOnly -and $entry.File -notlike '00-*'){continue}
        $file=Join-Path $photos $entry.File
        if($Bad -and $entry.File -eq 'allowed-a.jpg'){[IO.File]::WriteAllText($file,'invalid image bytes');continue}
        $image=[Drawing.Bitmap]::new(120,80);$graphics=[Drawing.Graphics]::FromImage($image)
        try{$graphics.Clear($entry.Color);$image.Save($file,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$image.Dispose()}
    }
    [IO.File]::WriteAllText((Join-Path $photos 'notes.txt'),'not an image')
    @{photo_sources=@($photos,$photos,(Join-Path $fixture 'missing'));exclude_patterns=@('Screenshots','Capturas de pantalla','Codestra-Wallpaper','\.cache','',$null)}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $folder 'config.json')
    return $fixture
}
function Check-Rotation($Result,[string]$ExpectedName,[int]$Width=1920,[int]$Height=1080){
    $folder=Join-Path $Result.Fixture 'Profile/Pictures/Codestra-Wallpaper'
    $state=Get-Content (Join-Path $folder 'state.json') -Raw|ConvertFrom-Json
    Assert ($state.selected.EndsWith($ExpectedName)) 'Rotation selected wrong or excluded photo'
    Assert ($state.presentation -eq 'medium-contained-centered-framed') 'Presentation contract drift'
    Assert ($Result.Ledger.ScreenReads -eq 1) 'Rotation did not use exactly one fake screen'
    Assert ($Result.Ledger.NativeCalls.Count -eq 1) 'Wallpaper native boundary was not exactly once'
    Assert ($Result.Ledger.NativeCalls[0].Action -eq 20 -and $Result.Ledger.NativeCalls[0].Flags -eq 3) 'Wallpaper boundary arguments changed'
    Assert ($Result.Ledger.RegistryCalls.Count -eq 2) 'Wallpaper registry requests changed'
    Assert ($Result.Ledger.InteropBlocked -eq 1) 'Source native interop was not intercepted exactly once'
    $output=[Drawing.Image]::FromFile((Join-Path $folder 'wallpaper.jpg'))
    try{
        Assert ($output.Width -eq $Width -and $output.Height -eq $Height) 'Canvas dimensions did not use fake screen/minimum bounds'
        $pixel=$output.GetPixel(0,0)
        Assert ([Math]::Abs($pixel.R-20) -le 12 -and [Math]::Abs($pixel.G-22) -le 12 -and [Math]::Abs($pixel.B-25) -le 12) 'Photo does not retain surrounding frame/background'
        $center=$output.GetPixel([int]($Width/2),[int]($Height/2))
        if($ExpectedName -like '*a.jpg'){Assert ($center.R -gt 180 -and $center.G -lt 70 -and $center.B -lt 70) 'Actual photo drawing/selection did not retain red image content'}
        else{Assert ($center.B -gt 180 -and $center.R -lt 70) 'Actual photo drawing/selection did not retain blue image content'}
        $horizontal=@(for($column=0;$column -lt $Width;$column++){$p=$output.GetPixel($column,[int]($Height/2));if(($ExpectedName -like '*a.jpg' -and $p.R -gt 180 -and $p.G -lt 70 -and $p.B -lt 70) -or ($ExpectedName -notlike '*a.jpg' -and $p.B -gt 180 -and $p.R -lt 70)){$column}})
        $vertical=@(for($row=0;$row -lt $Height;$row++){$p=$output.GetPixel([int]($Width/2),$row);if(($ExpectedName -like '*a.jpg' -and $p.R -gt 180 -and $p.G -lt 70 -and $p.B -lt 70) -or ($ExpectedName -notlike '*a.jpg' -and $p.B -gt 180 -and $p.R -lt 70)){$row}})
        $drawWidth=$horizontal[-1]-$horizontal[0]+1;$drawHeight=$vertical[-1]-$vertical[0]+1
        Assert ([Math]::Abs($drawWidth/$drawHeight-1.5) -lt 0.04) 'Photo aspect ratio was cropped or stretched'
        Assert ($drawWidth/$Width -le 0.71 -and $drawHeight/$Height -le 0.71 -and [Math]::Max($drawWidth/$Width,$drawHeight/$Height) -ge 0.68) 'Photo does not use approximately70percent contained geometry'
        Assert ([Math]::Abs(($horizontal[0]+$horizontal[-1])/2-$Width/2) -lt 5 -and [Math]::Abs(($vertical[0]+$vertical[-1])/2-$Height/2) -lt 5) 'Photo is not centered'

    }finally{$output.Dispose()}
    return $state
}
try{
    # Execute the production filter directly and reject unknown future commands/types.
    & "$PSScriptRoot/Test-PhotoExclusion.ps1" -RepositoryRoot $repository
    Assert ($LASTEXITCODE -in @(0,$null)) 'Photo exclusion regression failed'
    foreach($text in @('Remove-Item C:\\personal -Recurse','Microsoft.PowerShell.Management\Set-ItemProperty HKCU:\\X -Name X -Value 1','[System.Runtime.InteropServices.Marshal]::ReadInt32(0)','& ("power"+"cfg") /restoredefaultschemes','function Start-Process { }')){
        $denied=$false;try{$null=Assert-SourceSafety -Text $text}catch{$denied=$true};Assert $denied 'Unreviewed command/type/function passed preflight'
    }
    $result=Child BoundaryDenials (New-Fixture BoundaryDenials)
    Assert ($result.Ledger.BoundaryDenials -eq 8) 'Not all live-effect escape attempts were denied'
    Assert-NoExternalEffects $result

    foreach($scenario in @('Install','InstallTwice')){
        $fixture=New-Fixture $scenario;$social=Join-Path $fixture 'Profile/Desktop/Social Apps'
        [IO.File]::WriteAllText((Join-Path $social 'Legacy.lnk'),'preserve legacy shortcut')
        [IO.File]::WriteAllText((Join-Path $social 'GIVE THIS TO CLAUDE OR COPILOT notes.txt'),'preserve notes')
        $result=Child $scenario $fixture
        Assert ($result.Output.Contains('CODESTRA_WORKSTATION_INSTALL=PASS')) 'Installer did not reach completion'
        $links=@(Get-ChildItem $social -Filter *.lnk)
        Assert ($links.Count -eq 14) 'Installer did not produce 14 canonical shortcuts'
        $start=Join-Path $fixture 'Profile/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Social Apps'
        Assert (@(Get-ChildItem $start -Filter *.lnk).Count -eq 14) 'Start Menu shortcut set incomplete'
        Assert ($result.Ledger.Shortcuts.Count -eq $(if($scenario -eq 'InstallTwice'){56}else{28})) 'Shortcut COM stand-in call inventory changed'
        foreach($name in @('Rotate-CodestraWallpaper.ps1','Apply-CodestraUserShell.ps1')){
            $copied=Join-Path $fixture ('Profile/AppData/Local/Codestra/Workstation/'+$name)
            Assert ((Get-FileHash $copied).Hash -eq (Get-FileHash (Join-Path $repository ('windows/'+$name))).Hash) 'Installer copied unexpected script bytes'
        }

        Assert ((Get-Content (Join-Path $social 'Existing/Legacy.lnk') -Raw) -eq 'preserve legacy shortcut') 'Noncanonical shortcut bytes not preserved'
        Assert ((Get-Content (Join-Path $fixture 'Profile/Desktop/Codestra Work/Notes/GIVE THIS TO CLAUDE OR COPILOT notes.txt') -Raw) -eq 'preserve notes') 'Notes bytes not preserved'
        foreach($file in $links){$link=Get-Content $file.FullName -Raw|ConvertFrom-Json;Assert ($link.Arguments -match '^--app=https://.+ --start-maximized$') 'Shortcut app-mode URL contract changed'}
        $config=Get-Content (Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper/config.json') -Raw|ConvertFrom-Json
        Assert ($config.interval_minutes -eq 15 -and $config.image_fraction -eq 0.70) 'Wallpaper configuration changed'
        Assert ($config.exclude_patterns.Count -eq 4) 'Default exclusions changed'
        Assert ($result.Ledger.Tasks.Count -eq 2) 'Scheduled task inventory changed'
        foreach($task in $result.Ledger.Tasks.Values){
            Assert ($task.Principal.RunLevel -eq 'Limited' -and $task.Principal.LogonType -eq 'Interactive') 'Task privilege boundary changed'
            Assert ($task.Action.Execute -eq 'powershell.exe') 'Task executable changed'
            Assert ($task.Action.Argument.Contains('-NoProfile -ExecutionPolicy Bypass -File')) 'Existing task script contract changed'
        }
        $repeat=@($result.Ledger.Tasks['Codestra Wallpaper Rotation'].Trigger|Where-Object Once)[0]
        Assert ($repeat.RepetitionInterval.TotalMinutes -eq 15) 'Rotation repetition interval changed'
        Assert ($result.Ledger.Power.Count -eq $(if($scenario -eq 'InstallTwice'){8}else{4})) 'Power requests were not captured completely'
        Assert ($result.Ledger.TaskStarts.Count -eq $(if($scenario -eq 'InstallTwice'){4}else{2})) 'Task starts were not mocked/captured'
        Assert-NoExternalEffects $result
    }
    $result=Child InstallMissingEdge (New-Fixture InstallMissingEdge) 1
    Assert ($result.Ledger.Tasks.Count -eq 0 -and $result.Ledger.Power.Count -eq 0) 'Missing Edge proceeded to system configuration'
    Assert-NoExternalEffects $result

    $result=Child Apply (New-Fixture Apply)
    $shell=Get-Content (Join-Path $result.Fixture 'Profile/AppData/Local/Codestra/Workstation/shell-state.json') -Raw|ConvertFrom-Json
    Assert ($shell.dark_apps -eq 0 -and $shell.dark_system -eq 0 -and $shell.taskbar_centered -eq 1) 'Theme/taskbar readback incorrect'
    Assert ($shell.idle_seconds -eq '86400' -and $shell.secure_lock -eq '1') 'Secure lock readback incorrect'
    Assert ($result.Ledger.RegistryCalls.Count -eq 17) 'Registry request inventory changed'
    Assert ($result.Ledger.Processes.Count -eq 1) 'Shell refresh was not mocked'
    Assert-NoExternalEffects $result
    foreach($scenario in @('ApplyReadbackFailure','ApplyTaskbarFailure','ApplyLockFailure')){
        $result=Child $scenario (New-Fixture $scenario) 1
        Assert (-not (Test-Path (Join-Path $result.Fixture 'Profile/AppData/Local/Codestra/Workstation/shell-state.json'))) 'Failed critical readback published success state'
        Assert ($result.Ledger.Processes.Count -eq 0) 'Critical readback failure attempted shell refresh'
        Assert-NoExternalEffects $result
    }

    $result=Child VerifyMissing (New-Fixture VerifyMissing)
    $verification=$result.Output|ConvertFrom-Json
    Assert (-not $verification.wallpaper_exists -and -not $verification.shell_state_exists -and $verification.social_shortcuts -eq 0) 'Verification missing-state report incorrect'
    Assert-NoExternalEffects $result
    $fixture=New-Fixture VerifyPopulated;$folder=Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper';[IO.Directory]::CreateDirectory($folder)|Out-Null
    [IO.File]::WriteAllText((Join-Path $folder 'wallpaper.jpg'),'fixture bytes')
    @{selected='fixture-photo';presentation='medium-contained-centered-framed'}|ConvertTo-Json|Set-Content (Join-Path $folder 'state.json')
    $result=Child VerifyPopulated $fixture;$verification=$result.Output|ConvertFrom-Json
    Assert ($verification.wallpaper_exists -and $verification.selected_photo -eq 'fixture-photo' -and $verification.rotate_task -eq 'Ready' -and $verification.rotate_last_result -eq 0) 'Verification did not report actual fixture/mock state'
    Assert-NoExternalEffects $result

    if(-not $PortableOnly){
        Microsoft.PowerShell.Utility\Add-Type -AssemblyName System.Drawing
        $fixture=New-Fixture RotateMissingConfig;$result=Child RotateMissingConfig $fixture;Assert-NoExternalEffects $result
        $fixture=New-Fixture RotateEmpty;$folder=Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper';[IO.Directory]::CreateDirectory($folder)|Out-Null
        @{photo_sources=@((Join-Path $fixture 'Photos'));exclude_patterns=@('Screenshots')}|ConvertTo-Json|Set-Content (Join-Path $folder 'config.json')
        $result=Child RotateEmpty $fixture;Assert-NoExternalEffects $result
        $result=Child RotateExcludedOnly (Photo-Fixture RotateExcludedOnly -ExcludedOnly);Assert-NoExternalEffects $result
        $fixture=New-Fixture RotateInvalidConfig;$folder=Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper';[IO.Directory]::CreateDirectory($folder)|Out-Null
        [IO.File]::WriteAllText((Join-Path $folder 'config.json'),'not json');$result=Child RotateInvalidConfig $fixture 1;Assert-NoExternalEffects $result
        $result=Child RotateBadPhoto (Photo-Fixture RotateBadPhoto -Bad) 1
        Assert ($result.Ledger.NativeCalls.Count -eq 0 -and $result.Ledger.RegistryCalls.Count -eq 0) 'Invalid image proceeded to wallpaper changes'
        Assert ($result.Ledger.ScreenReads -eq 1) 'Invalid-image setup did not use the fake screen'
        $fixture=Photo-Fixture RotateFull
        $result=Child RotateFull $fixture;$state=Check-Rotation $result 'allowed-a.jpg';Assert ($state.index -eq 1) 'Duplicate sources were not deduplicated or +7 progression changed'
        $result=Child RotateFull $fixture;$state=Check-Rotation $result 'allowed-b.png';Assert ($state.index -eq 0) 'Persisted rotation state did not advance'
        $fixture=Photo-Fixture RotateCorruptState;[IO.File]::WriteAllText((Join-Path $fixture 'Profile/Pictures/Codestra-Wallpaper/state.json'),'invalid state')
        $null=Check-Rotation (Child RotateCorruptState $fixture) 'allowed-a.jpg'
        $null=Check-Rotation (Child RotateSmallScreen (Photo-Fixture RotateSmallScreen)) 'allowed-a.jpg' 1024 768
    }
    Assert ($script:Cases -eq $(if($PortableOnly){10}else{19})) 'Required child scenario inventory changed'
    @{status='PASS';child_cases=$script:Cases;assertions=$script:Assertions;portable_subset=[bool]$PortableOnly;real_registry_com_tasks_power_process_desktop_effects=$false;runtime_certification=$false}|ConvertTo-Json
}
finally{Microsoft.PowerShell.Management\Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
