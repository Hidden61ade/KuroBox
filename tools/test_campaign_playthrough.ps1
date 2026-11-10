param([Parameter(Mandatory=$true)][string]$GodotGui, [switch]$Headless)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$qaRoot = Join-Path $projectRoot '.tools\campaign_playthrough_project'
$engineRoot = Join-Path $projectRoot '.tools\godot_playthrough_portable'
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
Copy-Item -LiteralPath (Join-Path $projectRoot 'icon.svg'),(Join-Path $projectRoot 'icon.svg.import') -Destination $qaRoot -Force
$settings = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
$settings = $settings.Replace('KuroBox/runtime','KuroBox/campaign_playthrough_qa')
[System.IO.File]::WriteAllText((Join-Path $qaRoot 'project.godot'),$settings,[System.Text.UTF8Encoding]::new($false))
Set-Content -LiteralPath (Join-Path $qaRoot '.kuro_gameplay_validation_workspace') -Value 'isolated published campaign verification'
$evidence = Join-Path $qaRoot 'evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
Set-Content -LiteralPath (Join-Path $evidence '.gdignore') -Value ''
$importLog = Join-Path $evidence 'import.log'
$importRun = Start-Process -FilePath $portable -ArgumentList @('--headless','--editor','--path',('"'+$qaRoot+'"'),'--import','--quit','--log-file',('"'+$importLog+'"')) -WindowStyle Hidden -Wait -PassThru
if ($importRun.ExitCode -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)) { throw "Campaign copy import failed: $importLog" }
$log = Join-Path $evidence 'playthrough.log'
$reportPath = Join-Path $evidence 'campaign_playthrough_report.json'
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
$arguments = @('--path',('"'+$qaRoot+'"'),'--audio-driver','Dummy','--resolution','1280x720','--position','-2400,-2400','--log-file',('"'+$log+'"'),'--script','res://tests/test_campaign_playthrough.gd')
if ($Headless) { $arguments = @('--headless') + $arguments } else { $arguments += @('--','--capture') }
$windowStyle = if ($Headless) { 'Hidden' } else { 'Normal' }
$run = Start-Process -FilePath $portable -ArgumentList $arguments -WindowStyle $windowStyle -PassThru
$exited = $false
for ($attempt=0; $attempt -lt 7; $attempt++) {
    if ($run.WaitForExit(30000)) { $exited = $true; break }
    Write-Output 'Published campaign keyboard playthrough is still running...'
}
if (-not $exited) { $run.Kill(); throw 'Published campaign playthrough timed out.' }
if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $reportPath)) { throw "Campaign playthrough failed: $log" }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if ($report.failures.Count -gt 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked' -Quiet)) { throw "Campaign playthrough reported errors: $log" }
$output = Join-Path $projectRoot 'evidence'
Copy-Item -LiteralPath $reportPath -Destination $output -Force
Get-ChildItem -LiteralPath $evidence -Filter 'campaign_*.webp' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $output -Force }
Copy-Item -LiteralPath $log -Destination (Join-Path $output 'campaign_playthrough_validation.log') -Force
Write-Output ("Actual published campaign: {0} checks, {1} levels won through keyboard dispatch, {2} screenshots." -f $report.checks,$report.published_campaign.Count,$report.screenshots.Count)
