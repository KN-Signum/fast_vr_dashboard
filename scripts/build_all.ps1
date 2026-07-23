[CmdletBinding()]
param(
    [switch]$SkipFrontendChecks,
    [switch]$SkipPackageSmoke
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FrontendBuild = Join-Path $PSScriptRoot "build_frontend.ps1"
$BackendBuild = Join-Path $PSScriptRoot "build_backend.ps1"
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

if ($SkipPackageSmoke) {
    & $BackendBuild -SkipSmoke
} else {
    & $BackendBuild
}
if ($LASTEXITCODE -ne 0) {
    throw "Backend package build failed with exit code $LASTEXITCODE."
}

Write-Host "Frontend release, backend checks, and package build completed successfully."
