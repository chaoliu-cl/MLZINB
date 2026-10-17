param(
    [string]$ProfileRscript = 'C:/Program Files/R/R-4.4.2/bin/Rscript.exe',
    [switch]$Recompute
)
$ErrorActionPreference = 'Stop'
$ProfileTaskRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$ProfileBundleRoot = Split-Path -Parent $ProfileTaskRoot
$ProfileSelectedRoot = Join-Path $ProfileTaskRoot 'bikeshare_profile'
function Run-R([string]$Script, [string[]]$Arguments) {
    & $ProfileRscript (Join-Path $PSScriptRoot $Script) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "R step failed: $Script" }
}
function Run-Python([string]$Script, [string[]]$Arguments) {
    & py -3 (Join-Path $PSScriptRoot $Script) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python step failed: $Script" }
}
Push-Location -LiteralPath $ProfileBundleRoot
try {
    if ($Recompute) {
        $ProfileArchive = Join-Path $ProfileSelectedRoot ('archive_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-Item -ItemType Directory -Path $ProfileArchive | Out-Null
        foreach ($ProfileLeaf in @('outputs', 'figures')) {
            $ProfileTarget = Join-Path $ProfileSelectedRoot $ProfileLeaf
            if (Test-Path -LiteralPath $ProfileTarget) {
                $ProfileResolved = (Resolve-Path -LiteralPath $ProfileTarget).Path
                if (-not $ProfileResolved.StartsWith($ProfileSelectedRoot + [IO.Path]::DirectorySeparatorChar)) {
                    throw 'Archive target is outside the selected walkthrough.'
                }
                Move-Item -LiteralPath $ProfileResolved -Destination $ProfileArchive
            }
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ProfileTaskRoot 'bikeshare/source/hour.csv'))) {
        Run-Python 'download_bikeshare.py' @()
    }
    Run-Python 'prepare_bike.py' @()
    Run-R 'fit_profile.R' @('discovery','validation','full')
    Run-R 'export_bike_models.R' @('--profile','discovery','validation','full')
    Run-Python 'cluster_scores.py' @('--profile','discovery','validation','full')
    Run-Python 'build_profile_components.py' @()
    Run-R 'profile_components.R' @()
    Run-R 'profile_sensitivity.R' @('all')
    Run-R 'profile_dispersion_check.R' @()
    Run-Python 'collect_profile_sensitivity.py' @()
    if (-not (Test-Path -LiteralPath (Join-Path $ProfileSelectedRoot 'outputs/diagnostics/primary/residuals.csv'))) {
        Run-R 'profile_diagnostics.R' @('primary')
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ProfileSelectedRoot 'outputs/diagnostics/random_slope/residuals.csv'))) {
        Run-R 'profile_diagnostics.R' @('random_slope')
    }
    foreach ($ProfileDiagnostic in @('flexible_hour_joint','varying_dispersion')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProfileSelectedRoot ('outputs/diagnostics/' + $ProfileDiagnostic + '/residuals.csv')))) {
            Run-R 'profile_diagnostics.R' @($ProfileDiagnostic)
        }
    }
    Run-R 'profile_influence.R' @()
    Run-Python 'summarize_profile_influence.py' @()
    Run-Python 'profile_figures.py' @()
    Run-Python 'write_profile_report.py' @()
    Run-Python 'verify_profile_bundle.py' @()
} finally {
    Pop-Location
}
