[CmdletBinding()]
param(
    [switch]$AllowDirty,
    [switch]$ConfirmBrainAccessRedistribution
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BackendDirectory = Join-Path $RepoRoot "backend"

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        throw "Required command is not available on PATH: $Name"
    }
    return $Command.Source
}

function Find-InnoCompiler {
    $Command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    $Candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate -PathType Leaf) {
            return $Candidate
        }
    }
    throw "Inno Setup 6 compiler (ISCC.exe) was not found."
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "The client release must be built on Windows."
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw "The client release requires Windows x64."
}
if (
    -not $ConfirmBrainAccessRedistribution -and
    $env:VRDASH_CONFIRM_BRAINACCESS_REDISTRIBUTION -ne "1"
) {
    throw (
        "BrainAccess DLL redistribution has not been confirmed. " +
        "Review the SDK licence, then pass -ConfirmBrainAccessRedistribution."
    )
}

Require-Command "git" | Out-Null
Require-Command "uv" | Out-Null
Require-Command "flutter" | Out-Null
Require-Command "dart" | Out-Null
$InnoCompiler = Find-InnoCompiler

Push-Location $RepoRoot
try {
    if (-not $AllowDirty) {
        $GitStatus = & git status --porcelain --untracked-files=normal
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect the Git worktree."
        }
        if ($GitStatus) {
            throw (
                "The release worktree is not clean. Commit or remove changes, " +
                "or explicitly pass -AllowDirty for a non-production build."
            )
        }
    }

    & uv run --project $BackendDirectory --group package python `
        (Join-Path $PSScriptRoot "validate_windows_release.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Windows release source validation failed."
    }

    $PythonArchitecture = & uv run --project $BackendDirectory --group package `
        python -c "import platform; print(platform.machine())"
    if (
        $LASTEXITCODE -ne 0 -or
        $PythonArchitecture.Trim().ToLowerInvariant() -notin @("amd64", "x86_64")
    ) {
        throw "The backend build environment must use AMD64 Python."
    }
} finally {
    Pop-Location
}

Write-Host "Windows release preflight passed."
Write-Host "Inno Setup compiler: $InnoCompiler"
