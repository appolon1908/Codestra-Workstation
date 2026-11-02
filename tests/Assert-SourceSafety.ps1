function Assert-SourceSafety {
    param([Parameter(Mandatory)][string]$Text, [string]$Label = 'source')
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failure in $Label : $($errors -join '; ')" }
    $allowed = @('Add-Type','Test-Path','Get-Content','ConvertFrom-Json','Split-Path','Join-Path','Get-ChildItem','Where-Object','Sort-Object','New-Object','Get-Date','ConvertTo-Json','Set-Content','Set-ItemProperty','Out-Null','New-Item','Copy-Item','Select-Object','Move-Item','New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-TimeSpan','Register-ScheduledTask','powercfg','Start-ScheduledTask','Write-Output','whoami','Add-Content','Set-Dword','Set-String','Get-ItemProperty','Start-Process','Out-String','Get-ScheduledTask','Get-ScheduledTaskInfo')
    foreach ($command in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]}, $true)) {
        $name = $command.GetCommandName()
        if (-not $name -or $name -notin $allowed) { throw "Unreviewed command in $Label : $name" }
    }
    foreach ($function in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true)) {
        if ($function.Name -notin @('Set-Dword','Set-String')) { throw "Unreviewed function definition: $($function.Name)" }
    }
    $allowedTypes = @('string','string[]','int','Math','ordered','System.Drawing.Graphics','System.Drawing.Image','System.Drawing.Color','System.Drawing.Drawing2D.SmoothingMode','System.Drawing.Drawing2D.InterpolationMode','System.Drawing.Drawing2D.PixelOffsetMode','System.Drawing.Imaging.ImageFormat','System.Windows.Forms.Screen','CodestraWallpaperNative')
    foreach ($type in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst]}, $true)) {
        if ($type.TypeName.FullName -notin $allowedTypes) { throw "Unreviewed type: $($type.TypeName.FullName)" }
    }
    $allowedMethods = @('Max','Min','FromImage','FromFile','FromArgb','Dispose','Clear','FillRectangle','DrawImage','DrawRectangle','Save','SystemParametersInfo','CreateShortcut','AddMinutes','ToString')
    foreach ($method in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]}, $true)) {
        if ($method.Member.Value -notin $allowedMethods) { throw "Unreviewed method: $($method.Member.Value)" }
    }
    return $ast
}
