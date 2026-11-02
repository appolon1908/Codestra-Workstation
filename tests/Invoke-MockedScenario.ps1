param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$Scenario)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/Assert-SourceSafety.ps1"
$script:FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$script:RepositoryRoot=[IO.Path]::GetFullPath($RepositoryRoot)
$script:ReportPath=Join-Path $FixtureRoot 'mock-ledger.json'
$script:Ledger=@{Registry=@{};RegistryCalls=@();Tasks=@{};TaskStarts=@();Power=@();Shortcuts=@();Processes=@();NativeCalls=@();ScreenReads=0;InteropBlocked=0;Preflight=$false;Completed=$false}
function Save-Ledger { [IO.File]::WriteAllText($script:ReportPath,($script:Ledger|ConvertTo-Json -Depth 15)) }
function Safe-Path([string]$Path,[switch]$Source) {
    $normalized=$Path.Replace('\',[IO.Path]::DirectorySeparatorChar)
    $full=[IO.Path]::GetFullPath($normalized)
    $root=if($Source){Join-Path $script:RepositoryRoot 'windows'}else{$script:FixtureRoot}
    if(-not ($full.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw "OUTSIDE_FIXTURE_PATH=$Path"}
    return $full
}
# No source is executed until all four owned files pass the command/type allowlist.
$expected=@('Apply-CodestraUserShell.ps1','Install-CodestraProfessionalDesktop.ps1','Rotate-CodestraWallpaper.ps1','Verify-CodestraProfessionalDesktop.ps1')
$actual=@(Microsoft.PowerShell.Management\Get-ChildItem (Join-Path $RepositoryRoot 'windows') -File|ForEach-Object Name|Sort-Object)
if(($actual -join '|') -ne (($expected|Sort-Object)-join '|')){throw 'Unreviewed owned source inventory'}
foreach($name in $expected){ $null=Assert-SourceSafety -Text ([IO.File]::ReadAllText((Join-Path $RepositoryRoot "windows/$name"))) -Label $name }
$script:Ledger.Preflight=$true
$env:USERPROFILE=Join-Path $FixtureRoot 'Profile';$env:LOCALAPPDATA=Join-Path $env:USERPROFILE 'AppData/Local'
$env:APPDATA=Join-Path $env:USERPROFILE 'AppData/Roaming'

# Define safe managed stand-ins before a Forms assembly can ever be loaded.
foreach($assembly in [AppDomain]::CurrentDomain.GetAssemblies()){
    if($assembly.GetType('System.Windows.Forms.Screen',$false,$false)){throw 'A real Screen type was already loaded; isolation cannot be established'}
}
$safeTypes=Microsoft.PowerShell.Utility\Add-Type -PassThru -TypeDefinition @'
using System;
public class FixtureBounds { public int Width=1920; public int Height=1080; }
public class FixtureScreen { public FixtureBounds Bounds=new FixtureBounds(); }
namespace System.Windows.Forms {
 public class Screen {
  public static Action Read;
  public static FixtureScreen Value=new FixtureScreen();
  public static FixtureScreen PrimaryScreen { get { if(Read!=null) Read(); return Value; } }
 }
}
public class CodestraWallpaperNative {
 public static Action<int,int,string,int> Record;
 public static bool SystemParametersInfo(int action,int param,string value,int flags) {
  if(Record!=null) Record(action,param,value,flags); return true;
 }
}
'@
$screenStub=@($safeTypes|Where-Object FullName -eq 'System.Windows.Forms.Screen')[0]
if([System.Windows.Forms.Screen].Assembly -ne $screenStub.Assembly){throw 'Screen type did not bind to the safe stub'}
[System.Windows.Forms.Screen]::Read=[Action]{ $script:Ledger.ScreenReads++;Save-Ledger }
[CodestraWallpaperNative]::Record=[Action[int,int,string,int]]{param($action,$param,$value,$flags) $null=Safe-Path $value; $script:Ledger.NativeCalls+=@{Action=$action;Param=$param;Path=$value;Flags=$flags};Save-Ledger}
if($Scenario -eq 'RotateSmallScreen'){[System.Windows.Forms.Screen]::Value.Bounds.Width=800;[System.Windows.Forms.Screen]::Value.Bounds.Height=600}

function Test-Path {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path)
    if($Path -like 'HKCU:*'){return $script:Ledger.Registry.ContainsKey($Path)}
    if($Path -in @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe')){return $Scenario -ne 'InstallMissingEdge'}
    Microsoft.PowerShell.Management\Test-Path -LiteralPath (Safe-Path $Path)
}
function New-Item {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[string]$ItemType,[switch]$Force)
    if($Path -like 'HKCU:*'){$script:Ledger.Registry[$Path]=@{};Save-Ledger;return [pscustomobject]@{Name=$Path}}
    if($ItemType -ne 'Directory'){throw 'Unreviewed item creation type'}
    Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path (Safe-Path $Path) -Force:$Force
}
function Set-ItemProperty {
    [CmdletBinding()]param([string]$Path,[string]$Name,[object]$Value,[string]$Type)
    if($Path -notlike 'HKCU:*'){throw 'Only mocked HKCU properties are permitted'}
    if(-not $script:Ledger.Registry.ContainsKey($Path)){$script:Ledger.Registry[$Path]=@{}}
    $script:Ledger.Registry[$Path][$Name]=$Value;$script:Ledger.RegistryCalls+=@{Path=$Path;Name=$Name;Value=$Value};Save-Ledger
}
function Get-ItemProperty {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path)
    if($Path -notlike 'HKCU:*'){throw 'Only mocked registry readback is permitted'}
    $copy=@{};foreach($key in $script:Ledger.Registry[$Path].Keys){$copy[$key]=$script:Ledger.Registry[$Path][$key]}
    if($Scenario -eq 'ApplyReadbackFailure' -and $Path -like '*Themes\Personalize'){$copy.AppsUseLightTheme=1}
    if($Scenario -eq 'ApplyTaskbarFailure' -and $Path -like '*Explorer\Advanced'){$copy.TaskbarAl=0}
    if($Scenario -eq 'ApplyLockFailure' -and $Path -eq 'HKCU:\Control Panel\Desktop'){$copy.ScreenSaverIsSecure='0'}
    [pscustomobject]$copy
}
function Set-Content {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[Parameter(ValueFromPipeline,Position=1)][object]$Value,[string]$Encoding)
    begin{$values=@()};process{$values+=@($Value)};end{Microsoft.PowerShell.Management\Set-Content -LiteralPath (Safe-Path $Path) -Value $values -Encoding utf8}
}
function Add-Content {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[Parameter(ValueFromPipeline,Position=1)][object]$Value)
    process{Microsoft.PowerShell.Management\Add-Content -LiteralPath (Safe-Path $Path) -Value $Value}
}
function Get-Content {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[switch]$Raw)
    Microsoft.PowerShell.Management\Get-Content -LiteralPath (Safe-Path $Path) -Raw:$Raw
}
function Get-ChildItem {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[switch]$File,[switch]$Recurse,[string]$Filter)
    $parameters=@{LiteralPath=(Safe-Path $Path);File=$File;Recurse=$Recurse;ErrorAction='SilentlyContinue'}
    if($Filter){$parameters.Filter=$Filter}
    Microsoft.PowerShell.Management\Get-ChildItem @parameters
}
function Copy-Item {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Path,[Parameter(Position=1)][string]$Destination,[switch]$Force)
    $source=Safe-Path $Path -Source
    if([IO.Path]::GetFileName($source) -notin @('Rotate-CodestraWallpaper.ps1','Apply-CodestraUserShell.ps1')){throw 'Unexpected source copy'}
    Microsoft.PowerShell.Management\Copy-Item -LiteralPath $source -Destination (Safe-Path $Destination) -Force:$Force
}
function Move-Item {
    [CmdletBinding()]param([Parameter(ValueFromPipeline,Position=0)][object]$Path,[Parameter(Position=1)][string]$Destination,[switch]$Force)
    process{
        $source=if($Path -is [IO.FileInfo]){$Path.FullName}else{[string]$Path}
        Microsoft.PowerShell.Management\Move-Item -LiteralPath (Safe-Path $source) -Destination (Safe-Path $Destination) -Force:$Force
    }
}
function New-Object {
    [CmdletBinding()]param([Parameter(Position=0)][string]$TypeName,[Parameter(Position=1)][object[]]$ArgumentList,[string]$ComObject)
    if($ComObject){
        if($ComObject -ne 'WScript.Shell'){throw 'Unreviewed COM activation'}
        $shell=[pscustomobject]@{}
        $shell|Add-Member ScriptMethod CreateShortcut {
            param($path)
            $safe=Safe-Path $path
            $shortcut=[pscustomobject]@{CIPath=$safe;TargetPath='';Arguments='';WorkingDirectory='';IconLocation='';Description=''}
            $shortcut|Add-Member ScriptMethod Save {
                $null=Safe-Path $this.CIPath
                [IO.File]::WriteAllText($this.CIPath,($this|ConvertTo-Json))
                $script:Ledger.Shortcuts+=@{Path=$this.CIPath;Target=$this.TargetPath;Arguments=$this.Arguments};Save-Ledger
            }
            return $shortcut
        }
        return $shell
    }
    if($TypeName -notin @('System.Drawing.Bitmap','System.Drawing.SolidBrush','System.Drawing.Pen')){throw "Unreviewed constructor: $TypeName"}
    Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName -ArgumentList $ArgumentList
}
function Add-Type {
    [CmdletBinding()]param([Parameter(Position=0)][string]$TypeDefinition,[string]$AssemblyName)
    if($AssemblyName -eq 'System.Drawing'){Microsoft.PowerShell.Utility\Add-Type -AssemblyName System.Drawing;return}
    if($AssemblyName -eq 'System.Windows.Forms'){return} # Screen is the precompiled managed stub above.
    $normalized=$TypeDefinition.Replace("`r`n","`n").Trim()
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($normalized))).ToLowerInvariant()
    if($hash -ne 'd4d4c6531d53ada3756ff35ce8214283e2330b7a8031aa87f9a59d3651fc1aa5'){throw 'Unreviewed native interop definition'}
    $script:Ledger.InteropBlocked++;Save-Ledger # Never compile the source DllImport; only our managed stub exists.
}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskSettingsSet {param([switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) [pscustomobject]@{StartWhenAvailable=[bool]$StartWhenAvailable;AllowStartIfOnBatteries=[bool]$AllowStartIfOnBatteries;DontStopIfGoingOnBatteries=[bool]$DontStopIfGoingOnBatteries}}
function New-ScheduledTaskAction {param($Execute,$Argument) [pscustomobject]@{Execute=$Execute;Argument=$Argument}}
function New-ScheduledTaskTrigger {param([switch]$AtLogOn,$User,[switch]$Once,$At,$RepetitionInterval) [pscustomobject]@{AtLogOn=[bool]$AtLogOn;User=$User;Once=[bool]$Once;At=$At;RepetitionInterval=$RepetitionInterval}}
function Register-ScheduledTask {param($TaskName,$Action,$Trigger,$Principal,$Settings,[switch]$Force) $script:Ledger.Tasks[$TaskName]=@{Action=$Action;Trigger=$Trigger;Principal=$Principal;Settings=$Settings};Save-Ledger}
function Start-ScheduledTask {param($TaskName) if($TaskName -notin @('Codestra Professional Desktop','Codestra Wallpaper Rotation')){throw 'Unknown task start'};$script:Ledger.TaskStarts+=$TaskName;Save-Ledger}
function Get-ScheduledTask {[CmdletBinding()]param($TaskName) [pscustomobject]@{State='Ready'}}
function Get-ScheduledTaskInfo {[CmdletBinding()]param($TaskName) [pscustomobject]@{LastTaskResult=0}}
function powercfg { $value=$args -join ' ';if($value -notin @('/change monitor-timeout-ac 1440','/change monitor-timeout-dc 1440','/change standby-timeout-ac 0','/change standby-timeout-dc 0')){throw 'Unknown native power request'};$script:Ledger.Power+=$value;Save-Ledger }
function whoami { 'CI\FixtureUser' }
function Start-Process {[CmdletBinding()]param([Parameter(Position=0)]$FilePath,$ArgumentList,$WindowStyle) if($FilePath -ne 'rundll32.exe' -or $ArgumentList -ne 'user32.dll,UpdatePerUserSystemParameters'){throw 'Unknown process launch'};$script:Ledger.Processes+=@{File=$FilePath;Arguments=$ArgumentList};Save-Ledger}
# Assert that every OS effect command resolves to our function, never a cmdlet/native executable.
foreach($name in @('Test-Path','New-Item','Set-ItemProperty','Get-ItemProperty','New-Object','Add-Type','Start-Process','powercfg','whoami','New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet','New-ScheduledTaskAction','New-ScheduledTaskTrigger','Register-ScheduledTask','Start-ScheduledTask','Get-ScheduledTask','Get-ScheduledTaskInfo')){
    if((Get-Command $name).CommandType -ne 'Function'){throw "Missing isolation boundary: $name"}
}
$global:LASTEXITCODE=0
Save-Ledger
switch -Wildcard ($Scenario) {
    'BoundaryDenials' {
        $attempts=@(
            {Set-Content -Path (Join-Path ([IO.Path]::GetTempPath()) 'outside-codestra-fixture.txt') -Value 'forbidden'},
            {Get-ChildItem -Path ([IO.Path]::GetPathRoot($script:FixtureRoot))},
            {Set-ItemProperty -Path 'HKLM:\Software\Forbidden' -Name X -Value 1},
            {New-Object -ComObject WScript.Network},
            {New-Object -TypeName System.Net.WebClient},
            {Start-Process cmd.exe -ArgumentList '/c forbidden'},
            {powercfg /restoredefaultschemes},
            {Add-Type -TypeDefinition 'public class Unreviewed { }'}
        )
        $blocked=0
        foreach($attempt in $attempts){try{& $attempt}catch{$blocked++}}
        if($blocked -ne $attempts.Count){throw 'An OS boundary was not blocked'}
        $script:Ledger.BoundaryDenials=$blocked
    }
    'Install*' {
        . (Join-Path $RepositoryRoot 'windows/Install-CodestraProfessionalDesktop.ps1') -ProfilePath $env:USERPROFILE -PhotoSources @((Join-Path $FixtureRoot 'Photos')) -UserName 'CI\FixtureUser'
        if($Scenario -eq 'InstallTwice'){. (Join-Path $RepositoryRoot 'windows/Install-CodestraProfessionalDesktop.ps1') -ProfilePath $env:USERPROFILE -PhotoSources @((Join-Path $FixtureRoot 'Photos')) -UserName 'CI\FixtureUser'}
    }
    'Apply*' {. (Join-Path $RepositoryRoot 'windows/Apply-CodestraUserShell.ps1')}
    'Rotate*' {. (Join-Path $RepositoryRoot 'windows/Rotate-CodestraWallpaper.ps1') -ConfigPath (Join-Path $env:USERPROFILE 'Pictures/Codestra-Wallpaper/config.json')}
    'Verify*' {. (Join-Path $RepositoryRoot 'windows/Verify-CodestraProfessionalDesktop.ps1') -ProfilePath $env:USERPROFILE}
    default {throw 'Unknown isolated scenario'}
}
$script:Ledger.Completed=$true;$script:Ledger.SourceExit=$LASTEXITCODE;Save-Ledger
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
