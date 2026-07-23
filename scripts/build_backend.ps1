[CmdletBinding()]
param(
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BackendDirectory = Join-Path $RepoRoot "backend"
$BuildScript = Join-Path $PSScriptRoot "build_backend.py"

$UvArguments = @(
    "run",
    "--project",
    $BackendDirectory,
    "--group",
    "package",
    "python",
    $BuildScript
)
if ($SkipSmoke) {
    $UvArguments += "--skip-smoke"
}

& uv @UvArguments
if ($LASTEXITCODE -ne 0) {
    throw "Backend package build failed with exit code $LASTEXITCODE."
}
