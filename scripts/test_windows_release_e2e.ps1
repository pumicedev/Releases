param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,
    [string]$PackId = "Pumice.XR-ELS",
    [string]$Channel = "stable"
)

$ErrorActionPreference = "Stop"
$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$CurrentFullName = "$PackId-$CurrentVersion-$Channel-full.nupkg"
$CurrentFull = Get-ChildItem $ReleaseDir -Filter $CurrentFullName |
    Select-Object -First 1
if (-not $CurrentFull) {
    throw "Current full package is missing: $CurrentFullName"
}

$PreviousFull = Get-ChildItem $ReleaseDir -Filter "$PackId-*-$Channel-full.nupkg" |
    Where-Object { $_.FullName -ne $CurrentFull.FullName } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $PreviousFull) {
    throw "A previous full package is required for the two-version release gate"
}
$PreviousPrefix = "$PackId-"
$PreviousSuffix = "-$Channel-full.nupkg"
if (
    -not $PreviousFull.Name.StartsWith($PreviousPrefix) -or
    -not $PreviousFull.Name.EndsWith($PreviousSuffix)
) {
    throw "Could not parse previous version from $($PreviousFull.Name)"
}
$PreviousVersionLength =
    $PreviousFull.Name.Length - $PreviousPrefix.Length - $PreviousSuffix.Length
if ($PreviousVersionLength -le 0) {
    throw "Could not parse previous version from $($PreviousFull.Name)"
}
$PreviousVersion = $PreviousFull.Name.Substring(
    $PreviousPrefix.Length,
    $PreviousVersionLength
)
$PreviousSetup = Get-ChildItem $ReleaseDir -Filter "*Setup*.exe" |
    Where-Object { $_.Name -like "*$PreviousVersion*" } |
    Select-Object -First 1
if (-not $PreviousSetup) {
    throw "Previous Setup executable $PreviousVersion is required for the release gate"
}

# --silent prevents Setup from launching the server after installation. Passing
# EXE_ARGS through "--" triggers a Velopack 1.2.0/clap parser panic, and is not
# needed because the installed executable is verified explicitly below.
& $PreviousSetup.FullName --silent --installto $InstallRoot
if ($LASTEXITCODE -ne 0) {
    throw "Previous-version installation failed"
}

$UpdateExe = Join-Path $InstallRoot "Update.exe"
$ServerExe = Join-Path $InstallRoot "current\XR-ELS-Server.exe"
if (-not (Test-Path $UpdateExe) -or -not (Test-Path $ServerExe)) {
    throw "Velopack installation layout is incomplete"
}

function Assert-InstalledVersion([string]$Expected) {
    $Actual = (& $ServerExe --version | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or $Actual -ne $Expected) {
        throw "Expected installed version $Expected, got '$Actual'"
    }
}

Assert-InstalledVersion $PreviousVersion

& $UpdateExe --silent apply --package $CurrentFull.FullName --norestart
if ($LASTEXITCODE -ne 0) {
    throw "Local-feed update to $CurrentVersion failed"
}
Assert-InstalledVersion $CurrentVersion

& $UpdateExe --silent apply --package $PreviousFull.FullName --norestart
if ($LASTEXITCODE -ne 0) {
    throw "Program rollback to $PreviousVersion failed"
}
Assert-InstalledVersion $PreviousVersion

& $UpdateExe --silent apply --package $CurrentFull.FullName --norestart
if ($LASTEXITCODE -ne 0) {
    throw "Post-rollback update to $CurrentVersion failed"
}
Assert-InstalledVersion $CurrentVersion

Write-Host "Two-version install, update, launch, rollback, and re-update gate passed."
