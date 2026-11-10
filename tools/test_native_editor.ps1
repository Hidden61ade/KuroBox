param([Parameter(Mandatory=$true)][string]$GodotGui)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$qaRoot = Join-Path $projectRoot '.tools\native_editor_project'
$engineRoot = Join-Path $projectRoot '.tools\godot_portable'
if (-not (Test-Path -LiteralPath $GodotGui)) { throw 'Pass the official Godot 4.6 GUI executable.' }
New-Item -ItemType Directory -Path $qaRoot,$engineRoot -Force | Out-Null
$portable = Join-Path $engineRoot 'Godot.exe'
if (-not (Test-Path -LiteralPath $portable) -or (Get-FileHash -LiteralPath $portable).Hash -ne (Get-FileHash -LiteralPath $GodotGui).Hash) {
    Copy-Item -LiteralPath $GodotGui -Destination $portable -Force
}
Set-Content -LiteralPath (Join-Path $engineRoot '_sc_') -Value ''
foreach ($folder in @('addons','assets','content','core','features','tests')) {
    $destination = Join-Path $qaRoot $folder
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force }
}
foreach ($relative in @('content\workshop\drafts','content\workshop\proofs','.godot\kurobox_editor')) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $qaRoot $relative))
    if (-not $resolved.StartsWith($qaRoot + '\')) { throw 'QA cleanup escaped the isolated project.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    New-Item -ItemType Directory -Path $resolved -Force | Out-Null
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot'),(Join-Path $projectRoot 'icon.svg'),(Join-Path $projectRoot 'icon.svg.import') -Destination $qaRoot -Force
Set-Content -LiteralPath (Join-Path $qaRoot '.kuro_native_smoke_workspace') -Value 'isolated editor verification'
$evidence = Join-Path $qaRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
Set-Content -LiteralPath (Join-Path $evidence '.gdignore') -Value ''
$importLog = Join-Path $evidence 'import.log'
$importRun = Start-Process -FilePath $portable -ArgumentList @('--headless','--editor','--path',('"'+$qaRoot+'"'),'--import','--quit','--log-file',('"'+$importLog+'"')) -WindowStyle Hidden -Wait -PassThru
if ($importRun.ExitCode -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw "Isolated editor import failed: $importLog" }
$log = Join-Path $evidence 'native_smoke.log'
$reportPath = Join-Path $evidence 'native_editor_report.json'
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
$run = Start-Process -FilePath $portable -ArgumentList @('--editor','--path',('"'+$qaRoot+'"'),'--position','-2400,-2400','--resolution','1800x1100','--log-file',('"'+$log+'"'),'--','--kuro-workbench','--kuro-native-smoke') -WindowStyle Normal -PassThru
$exited = $false
for ($attempt=0; $attempt -lt 3; $attempt++) {
    if ($run.WaitForExit(30000)) { $exited = $true; break }
    Write-Output 'Waiting for the isolated native editor test...'
}
if (-not $exited) { $run.Kill(); throw 'Isolated native editor test timed out.' }
if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $reportPath)) { throw "Native editor test failed: $log" }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if ($report.failures.Count -gt 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked' -Quiet)) { throw "Native editor reported errors: $log" }
$output = Join-Path $projectRoot 'evidence'
Copy-Item -LiteralPath $reportPath -Destination $output -Force
Get-ChildItem -LiteralPath $evidence -Filter 'native_editor_*.png' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $output -Force }
Copy-Item -LiteralPath $log -Destination (Join-Path $output 'native_editor_validation.log') -Force
Write-Output ("Native editor: {0} checks passed; actual Editor screenshots copied to evidence/." -f $report.checks)
