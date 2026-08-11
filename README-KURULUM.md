# Rota360 Hastane Kurulum EXE Hazırlayıcı

Bu paket **Rota_Uygulamaa'nın güncel kaynak kodundan** tek bir
`Rota360_Hastane_Kurulum.exe` üretmek için hazırlanmıştır.

## Nihai hastane mimarisi

Hastane bilgisayarında:
- Rota360 Flutter Windows masaüstü uygulaması
- Local Node.js backend
- Local SQLite (`rota360.db`)

Bulutta:
- `route-backend` Render'da kalır.
- PostgreSQL/Neon mevcut merkezi backend altyapısında kalır.
- Mobil ile ortak rota/fleet verileri buradan kullanılır.

Hastane bilgisayarına PostgreSQL, Docker, Flutter SDK veya npm kurulmaz.

## TomTom API key

Key source code'a veya GitHub'a yazılmaz.

Installer build alınacak Windows PowerShell oturumunda:

```powershell
$env:TOMTOM_API_KEY="GERCEK_TOMTOM_KEY"
```

ardından build scripti çalıştırılır.

Build scripti şu komutu kullanır:

```powershell
flutter build windows --release --dart-define=TOMTOM_API_KEY=$env:TOMTOM_API_KEY
```

Not: Bir desktop istemciye derlenen API anahtarı binary içinden teorik olarak
çıkarılabilir. TomTom hesabında mümkün olan key kısıtları/limitleri ayrıca uygulanmalıdır.

## Developer PC gereksinimleri

- Windows 10/11 x64
- Flutter Windows desktop toolchain
- Visual Studio C++ desktop workload
- Node.js + npm
- Inno Setup 6
- Güncel `C:\src\Rota_Uygulamaa`

Kontrol:

```powershell
powershell -ExecutionPolicy Bypass -File .\CHECK-Build-PC.ps1
```

## Installer oluşturma

Bu dosyaları `C:\src\Rota_Uygulamaa` içine koyun veya scripti bulunduğu yerden
`-ProjectRoot` ile çalıştırın.

```powershell
$env:TOMTOM_API_KEY="GERCEK_TOMTOM_KEY"

powershell -ExecutionPolicy Bypass -File .\BUILD-Rota360-Hastane-Installer.ps1 `
  -ProjectRoot "C:\src\Rota_Uygulamaa"
```

Başarılı sonuç:

```text
C:\src\Rota_Uygulamaa\dist_hospital\Rota360_Hastane_Kurulum.exe
```

## Hastane bilgisayarında

Sadece `Rota360_Hastane_Kurulum.exe` kopyalanır ve çalıştırılır.

Kurulum:
- Programı `%LOCALAPPDATA%\Programs\Rota360` altına kurar.
- Local backend'i `%LOCALAPPDATA%\Rota360\backend` altına kurar.
- `%LOCALAPPDATA%\Rota360\backend\data` klasörünü oluşturur.
- Developer PC'deki test `rota360.db` dosyasını KOPYALAMAZ.
- Portable Node runtime'ı dahil eder.
- Masaüstüne `Rota360` kısayolu koyar.
- Kısayola basıldığında backend çalışmıyorsa otomatik başlatır.
- `127.0.0.1:3100/health` hazır olana kadar bekler ve sonra Rota360'ı açar.

Hastane personeli `npm start` veya `flutter run` kullanmaz.

## Local backend güvenliği

Backend mevcut kaynak koddaki gibi yalnızca:

```text
127.0.0.1:3100
```

üzerinde dinler.

SQLite dosyası localdir:

```text
%LOCALAPPDATA%\Rota360\backend\data\rota360.db
```

## Render cold-start

Render ücretsiz/uyuyan bir servis olarak çalışıyorsa ilk merkezi istek birkaç saniye
gecikebilir. Local Excel/SQLite kısmı bundan bağımsızdır.

## setupDrivers() UYARISI

Bu installer `route-backend`i hastane bilgisayarına kurmaz; backend Render'da kalır.

Ancak canlıya çıkmadan önce Render backend'deki `setupDrivers()` mutlaka kontrol edilmelidir.
Eğer fonksiyon `sürücü1..sürücü10` kullanıcılarını her restart'ta:

`ON CONFLICT ... DO UPDATE SET password_hash = ...`

ile güncelliyorsa, aynı kullanıcı adlarıyla manuel oluşturulmuş hesapların şifrelerini her
deploy/restart'ta yeniden `palyatifN` değerlerine çevirebilir.

- Manuel kullanıcı adları farklıysa çakışma yoktur.
- Aynıysa production öncesinde bu davranış düzeltilmelidir.
- Güvenli seçeneklerden biri mevcut hesapta `DO NOTHING` kullanmak veya seed işlemini
  açık bir tek-seferlik bootstrap'a çevirmektir.

## Kurum adı

Installer adı, kısayol ve ürün adı yalnızca `Rota360` olarak hazırlanmıştır.
Hastane adı branding'e eklenmemiştir.
