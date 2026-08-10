param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDir,
    [Parameter(Mandatory = $true)]
    [string]$CurrentVersion,
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$ReleaseDir = (Resolve-Path $ReleaseDir).Path
$CurrentFull = Get-ChildItem $ReleaseDir -Filter "*-$CurrentVersion-full.nupkg" |
    Select-Object -First 1
if (-not $CurrentFull) {
    throw "Current full package $CurrentVersion is missing"
}

$PreviousFull = Get-ChildItem $ReleaseDir -Filter "*-full.nupkg" |
    Where-Object { $_.FullName -ne $CurrentFull.FullName } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $PreviousFull) {
    throw "A previous full package is required for the two-version release gate"
}
if ($PreviousFull.Name -notmatch '-(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)-full\.nupkg$') {
    throw "Could not parse previous version from $($PreviousFull.Name)"
}
$PreviousVersion = $Matches.version
$PreviousSetup = Get-ChildItem $ReleaseDir -Filter "*Setup*.exe" |
    Where-Object { $_.Name -like "*$PreviousVersion*" } |
    Select-Object -First 1
if (-not $PreviousSetup) {
    throw "Previous Setup executable $PreviousVersion is required for the release gate"
}

& $PreviousSetup.FullName --silent --installto $InstallRoot -- --version
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
