[CmdletBinding()]
param(
    [switch]$SkipFrontendChecks
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FrontendBuild = Join-Path $PSScriptRoot "build_frontend.ps1"
$BackendDirectory = Join-Path $RepoRoot "backend"

if ($SkipFrontendChecks) {
    & $FrontendBuild -SkipChecks
} else {
    & $FrontendBuild
}
if ($LASTEXITCODE -ne 0) {
    throw "Frontend build failed with exit code $LASTEXITCODE."
}

Push-Location $BackendDirectory
try {
    & uv run --group dev pytest
    if ($LASTEXITCODE -ne 0) {
        throw "Backend tests failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

Write-Host "Frontend release and backend checks completed successfully."
