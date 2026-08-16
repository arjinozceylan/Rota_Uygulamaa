param(
    [string]$ProjectRoot = "C:\src\Rota_Uygulamaa",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail($Message) {
    Write-Host ""
    Write-Host "HATA: $Message" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "dist_hospital"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Rota360 Hastane Kurulum EXE Hazirlayici" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if (-not (Test-Path $ProjectRoot)) {
    Fail "Proje klasoru bulunamadi: $ProjectRoot"
}

# TomTom key kaynak koda yazilmaz. Build ortamindan alinmak zorunda.
if ([string]::IsNullOrWhiteSpace($env:TOMTOM_API_KEY)) {
    Fail @"
TOMTOM_API_KEY ortam degiskeni tanimli degil.

Bu PowerShell oturumunda once:
  `$env:TOMTOM_API_KEY="GERCEK_TOMTOM_KEY"

Sonra bu scripti tekrar calistirin.
"@
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { Fail "Flutter PATH'te bulunamadi." }

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Fail "Node.js PATH'te bulunamadi." }

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) { Fail "npm PATH'te bulunamadi." }

Set-Location $ProjectRoot

Write-Host ""
Write-Host "[1/9] Kaynak kod kontrolu..." -ForegroundColor Yellow
if (-not (Test-Path ".\pubspec.yaml")) { Fail "pubspec.yaml bulunamadi." }
if (-not (Test-Path ".\local_backend\server.js")) { Fail "local_backend\server.js bulunamadi." }
if (-not (Test-Path ".\local_backend\package.json")) { Fail "local_backend\package.json bulunamadi." }

# Hassas/test verisinin builder'a yanlislikla tasinmadigini sadece uyari olarak kontrol et.
if (Test-Path ".\local_backend\data\rota360.db") {
    Write-Host "UYARI: Developer PC'de local_backend\data\rota360.db var." -ForegroundColor DarkYellow
    Write-Host "Bu DB installer'a KOPYALANMAYACAK." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "[2/9] Flutter bagimliliklari ve analiz..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get basarisiz." }

flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) { Fail "flutter analyze basarisiz." }

Write-Host ""
Write-Host "[3/9] Windows Release build..." -ForegroundColor Yellow
flutter build windows --release --dart-define=TOMTOM_API_KEY=$env:TOMTOM_API_KEY
if ($LASTEXITCODE -ne 0) { Fail "Windows release build basarisiz." }

# Flutter surumlerine gore Release yolu degisebildigi icin dinamik bul.
$releaseDir = Get-ChildItem -Path (Join-Path $ProjectRoot "build\windows") -Directory -Recurse |
    Where-Object { $_.FullName -match "\\runner\\Release$" } |
    Select-Object -First 1

if (-not $releaseDir) {
    Fail "build\windows altinda runner\Release klasoru bulunamadi."
}

$appExe = Join-Path $releaseDir.FullName "rota_desktop.exe"
if (-not (Test-Path $appExe)) {
    $appExeObj = Get-ChildItem $releaseDir.FullName -Filter *.exe -File |
        Where-Object { $_.Name -notmatch "unins|crashpad" } |
        Select-Object -First 1
    if (-not $appExeObj) { Fail "Windows ana uygulama EXE'si bulunamadi." }
    $appExe = $appExeObj.FullName
}
$appExeName = Split-Path $appExe -Leaf

Write-Host "Windows uygulama EXE: $appExeName" -ForegroundColor Green

Write-Host ""
Write-Host "[4/9] Local backend Windows bagimliliklari..." -ForegroundColor Yellow
Push-Location (Join-Path $ProjectRoot "local_backend")
if (Test-Path ".\package-lock.json") {
    npm ci
} else {
    npm install
}
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Fail "local_backend npm bagimliliklari hazirlanamadi."
}
node --check server.js
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Fail "local_backend\server.js syntax hatasi."
}
Pop-Location

Write-Host ""
Write-Host "[5/9] Temiz installer staging alani..." -ForegroundColor Yellow
if (Test-Path $OutputRoot) {
    Remove-Item $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$staging = Join-Path $OutputRoot "staging"
$appStage = Join-Path $staging "app"
$backendStage = Join-Path $staging "backend"
New-Item -ItemType Directory -Force -Path $appStage,$backendStage | Out-Null

# Flutter Windows release'in TAMAMI gerekli.
Copy-Item (Join-Path $releaseDir.FullName "*") $appStage -Recurse -Force

# VC++ runtime DLL'lerini app-local dahil et.
$vcDlls = @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
foreach ($dll in $vcDlls) {
    $source = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $appStage $dll) -Force
    } else {
        Write-Warning "$dll bulunamadi. Hedef PC'de VC++ Redistributable gerekebilir."
    }
}

# Backend kaynaklari + Windows'ta kurulmus native node_modules.
Copy-Item ".\local_backend\server.js" $backendStage -Force
Copy-Item ".\local_backend\package.json" $backendStage -Force
if (Test-Path ".\local_backend\package-lock.json") {
    Copy-Item ".\local_backend\package-lock.json" $backendStage -Force
}
Copy-Item ".\local_backend\node_modules" $backendStage -Recurse -Force

# Node runtime portable olarak backend ile dagitilir.
Copy-Item $node.Source (Join-Path $backendStage "node.exe") -Force

# Bos data klasoru. Developer DB'si ASLA kopyalanmaz.
New-Item -ItemType Directory -Force -Path (Join-Path $backendStage "data") | Out-Null

Write-Host ""
Write-Host "[6/9] Guvenli launcher hazirlaniyor..." -ForegroundColor Yellow

$launcherPs1 = @'
$ErrorActionPreference = "SilentlyContinue"

$programDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $env:LOCALAPPDATA "Rota360\backend"
$nodeExe = Join-Path $backendDir "node.exe"
$serverJs = Join-Path $backendDir "server.js"
$appExe = Join-Path $programDir "app\rota_desktop.exe"

function Test-LocalBackend {
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:3100/health" -TimeoutSec 1
        return ($r.ok -eq $true)
    } catch {
        return $false
    }
}

if (-not (Test-LocalBackend)) {
    if (-not (Test-Path $nodeExe) -or -not (Test-Path $serverJs)) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "Rota360 yerel servis dosyalari bulunamadi. Kurulumu yeniden calistirin.",
            "Rota360",
            "OK",
            "Error"
        ) | Out-Null
        exit 1
    }

    Start-Process -FilePath $nodeExe `
        -ArgumentList "`"$serverJs`"" `
        -WorkingDirectory $backendDir `
        -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-LocalBackend) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "Rota360 yerel veri servisi baslatilamadi. Bilgi islem birimiyle iletisime gecin.",
            "Rota360",
            "OK",
            "Error"
        ) | Out-Null
        exit 1
    }
}

if (-not (Test-Path $appExe)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        "Rota360 uygulama dosyasi bulunamadi. Kurulumu yeniden calistirin.",
        "Rota360",
        "OK",
        "Error"
    ) | Out-Null
    exit 1
}

Start-Process -FilePath $appExe -WorkingDirectory (Split-Path -Parent $appExe)
'@

Set-Content -Path (Join-Path $staging "Start-Rota360.ps1") -Value $launcherPs1 -Encoding UTF8

$healthCheck = @'
Write-Host "=== Rota360 Kurulum Sonrasi Kontrol ===" -ForegroundColor Cyan

try {
    $health = Invoke-RestMethod "http://127.0.0.1:3100/health" -TimeoutSec 5
    Write-Host "Local backend: OK" -ForegroundColor Green
    $health | Format-List
} catch {
    Write-Host "Local backend: HATA" -ForegroundColor Red
    Write-Host $_.Exception.Message
}

try {
    $patients = Invoke-RestMethod "http://127.0.0.1:3100/patients" -TimeoutSec 5
    Write-Host "Aktif local adres kaydi: $($patients.Count)"
} catch {
    Write-Host "/patients kontrolu basarisiz." -ForegroundColor Red
}

try {
    $r = Invoke-WebRequest "https://route-backend-1.onrender.com/" -UseBasicParsing -TimeoutSec 20
    Write-Host "Render backend: HTTP $($r.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Render backend ilk baglantisi basarisiz/yavas olabilir." -ForegroundColor DarkYellow
}
'@
Set-Content -Path (Join-Path $staging "KurulumSonrasiKontrol.ps1") -Value $healthCheck -Encoding UTF8

Write-Host ""
Write-Host "[7/9] Inno Setup konfigurasyonu..." -ForegroundColor Yellow

# Not:
# Program dosyalari -> %LOCALAPPDATA%\Programs\Rota360
# Backend/SQLite -> %LOCALAPPDATA%\Rota360\backend
# Boylece app update/uninstall sırasında sonradan olusan rota360.db installer'a ait
# bir dosya olmadigi icin veri klasorunde kalir.
$iss = @"
#define MyAppName "Rota360"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Rota360"

[Setup]
AppId={{D6A62D72-508A-4F63-A93B-83409B9A3600}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Rota360
DefaultGroupName=Rota360
PrivilegesRequired=lowest
OutputDir=$OutputRoot
OutputBaseFilename=Rota360_Hastane_Kurulum
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\app\$appExeName
ArchitecturesAllowed=x64compatible

[Files]
Source: "$appStage\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "$backendStage\*"; DestDir: "{localappdata}\Rota360\backend"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "$staging\Start-Rota360.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "$staging\KurulumSonrasiKontrol.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{localappdata}\Rota360\backend\data"

; shared_preferences (uygulama arayuz onbellegi: surucu listesi, adres
; havuzu, secili sekme vb.) exe'nin CompanyName/ProductName bilgisinden
; turetilen bu klasorde tutuluyor - installer'in kurdugu {localappdata}
; klasorunun DISINDA oldugu icin normal bir yeniden kurulum bunu SILMIYOR.
; Onceki kurulumda tam bu yuzden "eski onbellegi elle silmeden calismadi"
; sorunu yasandi. Hastanin SQLite verisi ({localappdata}\Rota360\backend\data)
; buna dahil degil, ona hic dokunulmuyor.
[InstallDelete]
Type: filesandordirs; Name: "{userappdata}\Rota360\Rota360"

[Icons]
Name: "{group}\Rota360"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-Rota360.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\app\$appExeName"
Name: "{autodesktop}\Rota360"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-Rota360.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\app\$appExeName"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Start-Rota360.ps1"""; Description: "Rota360'i baslat"; Flags: postinstall nowait skipifsilent
"@

$issPath = Join-Path $OutputRoot "Rota360_Hastane_Kurulum.iss"
Set-Content -Path $issPath -Value $iss -Encoding UTF8

Write-Host ""
Write-Host "[8/9] Inno Setup derleyici kontrolu..." -ForegroundColor Yellow
$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $iscc) {
    Write-Host ""
    Write-Host "Inno Setup 6 bulunamadi." -ForegroundColor DarkYellow
    Write-Host "Staging ve .iss dosyasi hazirlandi:" -ForegroundColor DarkYellow
    Write-Host "  $issPath"
    Write-Host ""
    Write-Host "Inno Setup 6'yi developer PC'ye kurup scripti tekrar calistirin."
    exit 2
}

Write-Host ""
Write-Host "[9/9] Tek kurulum EXE'si derleniyor..." -ForegroundColor Yellow
& $iscc $issPath
if ($LASTEXITCODE -ne 0) {
    Fail "Inno Setup EXE derlemesi basarisiz."
}

$installer = Join-Path $OutputRoot "Rota360_Hastane_Kurulum.exe"

if (-not (Test-Path $installer)) {
    Fail "Installer beklenen yerde olusmadi: $installer"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " KURULUM DOSYASI HAZIR" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host $installer -ForegroundColor Green
Write-Host ""
Write-Host "TEST rota360.db installer'a dahil edilmedi."
Write-Host "Hastane PC'de Node.js, npm, Flutter veya PostgreSQL kurulmasi gerekmeyecek."
Write-Host "Rota360 kisayolu local backend'i otomatik baslatacak."
