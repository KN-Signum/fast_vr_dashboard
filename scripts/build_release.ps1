[CmdletBinding()]
param(
    [switch]$AllowDirty,
    [switch]$ConfirmBrainAccessRedistribution,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BackendDirectory = Join-Path $RepoRoot "backend"
$PackageDirectory = Join-Path $RepoRoot "dist\PanelVR"
$PackageExecutable = Join-Path $PackageDirectory "PanelVR.exe"
$InstallerScript = Join-Path $RepoRoot "installer\PanelVR.iss"
$InstallerOutput = Join-Path $RepoRoot "build\installer"
$ReleaseRoot = Join-Path $RepoRoot "release"
$Preflight = Join-Path $PSScriptRoot "preflight_windows.ps1"
$BuildAll = Join-Path $PSScriptRoot "build_all.ps1"

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

function Find-SignTool {
    $Command = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    $KitsBin = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path $KitsBin -PathType Container) {
        $Candidate = Get-ChildItem $KitsBin -Filter "signtool.exe" -Recurse |
            Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($null -ne $Candidate) {
            return $Candidate.FullName
        }
    }
    throw "signtool.exe was not found in PATH or the Windows 10 SDK."
}

function Sign-And-Verify {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SignTool
    )

    & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 `
        /tr $TimestampUrl /td SHA256 $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode signing failed: $Path"
    }
    $Signature = Get-AuthenticodeSignature $Path
    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode signature is not valid for $Path`: $($Signature.Status)"
    }
}

$PreflightArguments = @{}
if ($AllowDirty) {
    $PreflightArguments["AllowDirty"] = $true
}
if ($ConfirmBrainAccessRedistribution) {
    $PreflightArguments["ConfirmBrainAccessRedistribution"] = $true
}
& $Preflight @PreflightArguments

& $BuildAll
if ($LASTEXITCODE -ne 0) {
    throw "Application build failed with exit code $LASTEXITCODE."
}

$Signed = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)
if ($Signed) {
    $SignTool = Find-SignTool
    Sign-And-Verify -Path $PackageExecutable -SignTool $SignTool
} else {
    Write-Warning (
        "No certificate thumbprint was provided. The release will be unsigned " +
        "and may trigger Microsoft Defender SmartScreen."
    )
}

& uv run --project $BackendDirectory --group package python `
    (Join-Path $PSScriptRoot "finalize_backend_package.py")
if ($LASTEXITCODE -ne 0) {
    throw "Could not finalize the signed backend package."
}
if ($Signed) {
    & uv run --project $BackendDirectory --group package python `
        (Join-Path $PSScriptRoot "smoke_test_package.py")
    if ($LASTEXITCODE -ne 0) {
        throw "The signed backend package failed its runtime smoke test."
    }
}

$Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
$InnoCompiler = Find-InnoCompiler
New-Item -ItemType Directory -Path $InstallerOutput -Force | Out-Null
& $InnoCompiler `
    "/DAppVersion=$Version" `
    "/DSourceDir=$PackageDirectory" `
    "/DOutputDir=$InstallerOutput" `
    $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
}

$Installer = Join-Path $InstallerOutput "PanelVR-Setup-$Version-win-x64.exe"
if (-not (Test-Path $Installer -PathType Leaf)) {
    throw "Expected installer was not created: $Installer"
}
if ($Signed) {
    Sign-And-Verify -Path $Installer -SignTool $SignTool
}

$AssemblyArguments = @(
    "run",
    "--project",
    $BackendDirectory,
    "--group",
    "package",
    "python",
    (Join-Path $PSScriptRoot "assemble_windows_release.py"),
    "--installer",
    $Installer,
    "--package",
    $PackageDirectory,
    "--release-root",
    $ReleaseRoot
)
if ($Signed) {
    $AssemblyArguments += "--signed"
}
& uv @AssemblyArguments
if ($LASTEXITCODE -ne 0) {
    throw "Windows release assembly failed with exit code $LASTEXITCODE."
}

Write-Host "Client release completed: $(Join-Path $ReleaseRoot $Version)"
