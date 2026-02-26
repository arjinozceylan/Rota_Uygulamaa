# rota_desktop

Google Maps API baglantisi (adres otomatik tamamlama) projeye eklendi.

## Kurulum

1. Google Cloud Console'da bir proje olustur.
2. `Places API` servisini etkinlestir.
3. Bu uygulama icin bir API key olustur.
4. API key'i koda yazma; uygulamayi `--dart-define` ile calistir:

```bash
flutter pub get
flutter run --dart-define=GOOGLE_MAPS_API_KEY=YOUR_API_KEY
```

## Notlar

- Adres arama kutusu Google Places Autocomplete API'ye baglidir.
- API key verilmezse uygulama otomatik olarak mock onerilere geri duser.
- Uretimde API key kisitlari (app restriction + API restriction) mutlaka acilmalidir.
