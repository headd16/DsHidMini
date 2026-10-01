param([Parameter(Mandatory)][string]$SetupPath)
$ErrorActionPreference = 'Stop'
$diagnostics = Join-Path $PWD 'DualController/artifacts/install-diagnostics'
New-Item -ItemType Directory -Force $diagnostics | Out-Null

function Invoke-BoundedInstaller([string]$FilePath, [string[]]$Arguments, [int[]]$AllowedExitCodes) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
    $handle = $process.Handle
    if (-not $process.WaitForExit(180000)) {
        & taskkill /PID $process.Id /T /F
        throw "Installer timed out: $FilePath"
    }
    $process.Refresh()
    $code = $process.ExitCode
    Write-Host "Installer exit code: $code ($FilePath)"
    if ($code -notin $AllowedExitCodes) { throw "Unexpected installer exit code: $code" }
    return $code
}

$originalName = 'Nefarius_DsHidMini_Drivers_x64_arm64_v3.17.1.msi'
$source = Resolve-Path "DualController/artifacts/dependencies/$originalName"
$hash = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
$legacyFolder = Join-Path $env:RUNNER_TEMP ('renamed-dshidmini-' + [guid]::NewGuid())
New-Item -ItemType Directory $legacyFolder | Out-Null
$legacyMsi = Join-Path $legacyFolder 'DsHidMini.msi'
Copy-Item $source $legacyMsi
# The preceding first-install test registered the original source filename.
# Put ONLY the old shortened name in an isolated folder to exercise the
# same SecureRepair lookup seen in the user's existing-install failure log.
$legacyLog = Join-Path $diagnostics 'old-renamed-msi.log'
$legacyExit = Invoke-BoundedInstaller "$env:SystemRoot/System32/msiexec.exe" `
    @('/i', "`"$legacyMsi`"", '/qn', '/norestart', '/L*vx!', "`"$legacyLog`"") @(0,3010,1603)
$legacyText = Get-Content $legacyLog -Raw
$reproduced = $legacyExit -eq 1603 -and $legacyText -match 'SECUREREPAIR: SecureRepair Failed'
Write-Host "Old renamed-source SecureRepair failure reproduced: $reproduced"

$repeatLog = Join-Path $diagnostics 'corrected-reinstallation.log'
$repeatExit = Invoke-BoundedInstaller (Resolve-Path $SetupPath) `
    @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/RESTARTEXITCODE=3010',
      '/COMPONENTS=bridge,ps3', "/LOG=`"$repeatLog`"") @(0,3010)
Get-Content $repeatLog -Tail 80

$cache = Join-Path $env:ProgramData "DualController/PackageCache/$hash"
foreach ($name in $originalName,'DsHidMini.msi') {
    if ((Get-FileHash (Join-Path $cache $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
        throw "Retained MSI source hash mismatch: $name"
    }
}
foreach ($path in @(
    "$env:ProgramFiles/DualController/DualController.exe",
    "$env:ProgramFiles/Nefarius Software Solutions/DsHidMini/ControlApp.exe",
    "$env:ProgramFiles/Nefarius Software Solutions/DsHidMini/drivers/dshidmini.inf")) {
    if (-not (Test-Path $path)) { throw "Installed file missing: $path" }
}
[ordered]@{
    OldRenamedMsiExitCode = $legacyExit
    OldSecureRepairFailureReproduced = $reproduced
    CorrectedReinstallationExitCode = $repeatExit
    RetainedSourceAndAliasHashVerified = $true
    InstalledFilesVerified = $true
} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $diagnostics 'reinstallation-check.json')
