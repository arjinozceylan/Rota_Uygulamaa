# Rota360 - Developer PC Installer Ön Kontrolü

Write-Host "=== Rota360 Installer On Kontrol ===" -ForegroundColor Cyan

$failed = $false

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Flutter: BULUNAMADI" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "Flutter: OK" -ForegroundColor Green
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js: BULUNAMADI" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "Node.js: OK" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($env:TOMTOM_API_KEY)) {
    Write-Host "TOMTOM_API_KEY: TANIMLI DEGIL" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "TOMTOM_API_KEY: TANIMLI" -ForegroundColor Green
}

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
    Write-Host "Inno Setup 6: OK" -ForegroundColor Green
} else {
    Write-Host "Inno Setup 6: BULUNAMADI" -ForegroundColor Red
    $failed = $true
}

if ($failed) { exit 1 }
