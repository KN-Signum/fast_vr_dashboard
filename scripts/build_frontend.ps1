[CmdletBinding()]
param(
    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BackendDirectory = Join-Path $RepoRoot "backend"
$BuildScript = Join-Path $PSScriptRoot "build_frontend.py"

$UvArguments = @(
    "run",
    "--project",
    $BackendDirectory,
    "python",
    $BuildScript
)
if ($SkipChecks) {
    $UvArguments += "--skip-checks"
}

& uv @UvArguments
if ($LASTEXITCODE -ne 0) {
    throw "Frontend release build failed with exit code $LASTEXITCODE."
}
