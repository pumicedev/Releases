param(
    [Parameter(Mandatory = $true)]
    [string[]]$Files,
    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,
    [Parameter(Mandatory = $true)]
    [string]$CertificatePassword
)

$ErrorActionPreference = "Stop"
$SignTool = (Get-Command signtool.exe -ErrorAction Stop).Source

foreach ($File in $Files) {
    if (-not (Test-Path $File -PathType Leaf)) {
        throw "Signing target is missing: $File"
    }
    & $SignTool sign /fd SHA256 /f $CertificatePath /p $CertificatePassword /tr "http://timestamp.digicert.com" /td SHA256 $File
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $File"
    }
    & $SignTool verify /pa /all $File
    if ($LASTEXITCODE -ne 0) {
        throw "Authenticode verification failed for $File"
    }
}
