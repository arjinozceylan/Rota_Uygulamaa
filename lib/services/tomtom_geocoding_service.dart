import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/models/address.dart';
import '../config/app_config.dart';

/// Tek bir arama denemesinin sonucu. [wasRateLimited] true ise çağıran taraf
/// (bkz. home_page.dart'taki adaptif hız kontrolü) yavaşlayıp aynı sorguyu
/// tekrar denemeli — burada sabit bir bekleme/yeniden deneme yapılmıyor,
/// çünkü hesabın gerçek hız sınırı bilinmiyor ve bu karar tüm içe aktarım
/// boyunca paylaşılan, kendini ayarlayan bir mekanizmaya bırakılıyor.
class TomTomGeocodeAttempt {
  final List<Address> addresses;
  final bool wasRateLimited;
  const TomTomGeocodeAttempt(this.addresses, this.wasRateLimited);
}

/// TomTom Geocoding API ile adres arama servisi.
///
/// OsmPlacesService (Nominatim) ile aynı amaca hizmet eder ama sadece CSV
/// toplu adres içe aktarımında kullanılır: Nominatim'in genel/ücretsiz
/// servisi saniyede ~1 istekle ve toplu/otomatik kullanıma kapalı olduğu
/// için binlerce adreslik listelerde 429 (Too Many Requests) ve CORS
/// hatalarıyla tıkanıyordu. TomTom ücretli ama çok daha yüksek hızda ve
/// güvenilir çalışıyor.
///
/// Uygulamanın diğer, düşük hacimli arama akışları (yazarken öneri, ters
/// geocoding) bilinçli olarak Nominatim'de bırakıldı — maliyeti sadece
/// gerçekten gerektiği yerde (toplu içe aktarım) üstleniyoruz.
class TomTomGeocodingService {
  const TomTomGeocodingService();

  static const String _host = 'api.tomtom.com';

  static bool get isConfigured => AppConfig.tomtomApiKey.isNotEmpty;

  Future<TomTomGeocodeAttempt> search({
    required String query,
    int limit = 1,
    String countryCode = 'TR',
    String language = 'tr-TR',
  }) async {
    final q = query.trim();
    if (q.isEmpty || !isConfigured) {
      return const TomTomGeocodeAttempt([], false);
    }

    // Uri.https(host, path, ...) verdiğimiz path string'ini '/' karakterine
    // göre segmentlere ayırır — adres metninde '/' geçerse (Türkçe
    // adreslerde "No:5/3", "Blok A/2" gibi çok yaygın) bu bir URL ayırıcı
    // sanılıp istek bozuluyor ve 404 dönüyordu. pathSegments kullanarak
    // sorgu metnini TEK bir segment olarak veriyoruz; içindeki '/' dahil
    // her özel karakter doğru şekilde %-encode edilir.
    final uri = Uri(
      scheme: 'https',
      host: _host,
      pathSegments: ['search', '2', 'geocode', '$q.json'],
      queryParameters: {
        'key': AppConfig.tomtomApiKey,
        'limit': limit.toString(),
        'countrySet': countryCode,
        'language': language,
      },
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 429) {
        return const TomTomGeocodeAttempt([], true);
      }
      if (res.statusCode != 200) {
        return const TomTomGeocodeAttempt([], false);
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final results = decoded['results'] as List? ?? [];

      final addresses = results
          .map((r) {
            final m = r as Map<String, dynamic>;
            final position = m['position'] as Map<String, dynamic>?;
            final address = m['address'] as Map<String, dynamic>?;
            final lat = (position?['lat'] as num?)?.toDouble();
            final lon = (position?['lon'] as num?)?.toDouble();
            final display = address?['freeformAddress']?.toString() ?? '';
            final id = m['id']?.toString() ?? '';

            return Address(
              code: 'TT',
              address: display,
              placeId: 'tomtom:$id',
              lat: lat,
              lng: lon,
            );
          })
          .where((a) => a.address.trim().isNotEmpty && a.hasCoordinates)
          .toList();

      return TomTomGeocodeAttempt(addresses, false);
    } catch (_) {
      return const TomTomGeocodeAttempt([], false);
    }
  }
}
