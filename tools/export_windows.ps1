param([string]$GodotBin = $env:GODOT_BIN, [switch]$FetchTemplates)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $GodotBin) {
    $candidate = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $GodotBin = $candidate.Source }
}
$template = Join-Path $projectRoot '.tools\windows_export\windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) {
    if (-not $FetchTemplates) { throw 'Official 4.6 templates are missing. Rerun with -FetchTemplates to download only Windows templates.' }
    & python (Join-Path $PSScriptRoot 'fetch_windows_templates.py')
    if ($LASTEXITCODE -ne 0) { throw 'Template acquisition failed.' }
}
& (Join-Path $PSScriptRoot 'validate.ps1') -GodotBin $GodotBin
$buildRoot = Join-Path $projectRoot 'builds\windows'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$destination = Join-Path $buildRoot 'KuroBox.exe'
& $GodotBin --headless --path $projectRoot --export-release 'Windows Desktop' $destination
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
$releaseLog = Join-Path $projectRoot 'evidence\release_validation.log'
$nativeRun = Start-Process -FilePath $destination -ArgumentList @('--headless','--log-file',('"' + $releaseLog + '"'),'--','--self-check') -WindowStyle Hidden -Wait -PassThru
if ($nativeRun.ExitCode -ne 0 -or -not (Select-String -LiteralPath $releaseLog -Pattern 'RELEASE_SELF_CHECK .*"failures":\[\]' -Quiet)) { throw 'Exported runtime self-check failed.' }
if (Select-String -LiteralPath $releaseLog -Pattern 'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked' -Quiet) { throw "Exported runtime reported an error. See $releaseLog" }
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md'), (Join-Path $projectRoot 'CREDITS.md') -Destination $buildRoot -Force
Write-Output "Exported and verified $destination"
