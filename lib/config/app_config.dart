class AppConfig {
  /// TomTom Geocoding API anahtarı. CSV toplu adres içe aktarımında
  /// kullanılır (bkz. tomtom_geocoding_service.dart) — Nominatim'in
  /// saniyede-1-istek kısıtı büyük listelerde (binlerce adres) engellenmeye
  /// yol açtığı için toplu geocoding burada TomTom'a taşındı.
  /// Boşsa toplu içe aktarım Nominatim'e (yavaş ama ücretsiz) geri düşer.
  static const String tomtomApiKey = String.fromEnvironment('TOMTOM_API_KEY');
}
