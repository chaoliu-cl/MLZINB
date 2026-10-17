param(
  [ValidateSet('full','smoke','calibration')][string]$Mode='full',
  [int]$Replications=500,
  [int]$Workers=2,
  [string]$Label='production_2026-10-16',
  [string]$Conditions='all',
  [string]$Rscript='C:\Program Files\R\R-4.4.2\bin\Rscript.exe',
  [switch]$Foreground,
  [switch]$Status
)
$ErrorActionPreference='Stop'
if ($Label -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid label.' }
$simRoot=$PSScriptRoot
$simRun=Join-Path $simRoot "runs\$Label"
if ($Status) {
  Get-Content -LiteralPath (Join-Path $simRun 'status.json')
  $simCheckpointDir=Join-Path $simRun 'checkpoints'
  if (Test-Path -LiteralPath $simCheckpointDir) {
    Write-Output "Atomic checkpoints currently on disk: $(@(Get-ChildItem -LiteralPath $simCheckpointDir -Filter '*.rds').Count)"
  }
  $simProgressDir=Join-Path $simRun 'task_progress'
  if (Test-Path -LiteralPath $simProgressDir) {
    Get-ChildItem -LiteralPath $simProgressDir -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName }
  }
  return
}
if (-not (Test-Path -LiteralPath $Rscript)) { throw "Rscript not found: $Rscript" }
if ($Replications -lt 1 -or $Replications -gt 100000) { throw 'Replications must be 1..100000.' }
$env:OMP_NUM_THREADS='1'
$env:OPENBLAS_NUM_THREADS='1'
$env:MKL_NUM_THREADS='1'
$env:LC_ALL='C'
$env:LANG='C'
New-Item -ItemType Directory -Path $simRun -Force | Out-Null
$simScript=Join-Path $simRoot 'run.R'
$simArgs=@('--vanilla',"`"$simScript`"","--mode=$Mode","--reps=$Replications","--workers=$Workers","--label=$Label","--conditions=$Conditions")
if ($Foreground) {
  & $Rscript --vanilla $simScript "--mode=$Mode" "--reps=$Replications" "--workers=$Workers" "--label=$Label" "--conditions=$Conditions"
  if ($LASTEXITCODE -ne 0) { throw "Simulation exited with code $LASTEXITCODE" }
} else {
  # Do not leave a visible console open on the user's desktop.
  $simProcess=Start-Process -FilePath $Rscript -ArgumentList $simArgs -WorkingDirectory $simRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $simRun 'controller.stdout.log') `
    -RedirectStandardError (Join-Path $simRun 'controller.stderr.log')
  Set-Content -LiteralPath (Join-Path $simRun 'launcher_pid.txt') -Value $simProcess.Id
  Write-Output "Started process $($simProcess.Id). Status: $simRun\status.json"
}
