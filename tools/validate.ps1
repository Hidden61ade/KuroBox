param([string]$GodotBin = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $GodotBin) {
    $candidate = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $GodotBin = $candidate.Source }
}
if (-not $GodotBin -or -not (Test-Path -LiteralPath $GodotBin)) { throw 'Pass -GodotBin with the Godot 4.6 console executable path.' }
$engineVersion = & $GodotBin --version
if ($engineVersion -notmatch '^4\.6\.') { throw "Godot 4.6 is required. Found: $engineVersion" }
$evidenceRoot = Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$jobs = @('import','core','parameters','replay','workspace','editor','editor_workbench','recovery','profile','assets','transition','flow','hud_footer')
foreach ($job in $jobs) {
    $logPath = Join-Path $evidenceRoot ($job + '_validation.log')
    if ($job -eq 'import') {
        & $GodotBin --headless --path $projectRoot --log-file $logPath --editor --import --quit
    } else {
        & $GodotBin --headless --path $projectRoot --log-file $logPath --script ("res://tests/test_{0}.gd" -f $job)
    }
    if ($LASTEXITCODE -ne 0) { throw "$job failed with exit code $LASTEXITCODE. See $logPath" }
    if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked' -Quiet) { throw "$job reported an engine error. See $logPath" }
}
Write-Output "KuroBox validation passed with $engineVersion."
