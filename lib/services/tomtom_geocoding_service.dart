import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/models/address.dart';
import '../config/app_config.dart';

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

  Future<List<Address>> search({
    required String query,
    int limit = 1,
    String countryCode = 'TR',
    String language = 'tr-TR',
  }) async {
    final q = query.trim();
    if (q.isEmpty || !isConfigured) return [];

    Future<http.Response> doRequest() {
      final uri = Uri.https(_host, '/search/2/geocode/$q.json', {
        'key': AppConfig.tomtomApiKey,
        'limit': limit.toString(),
        'countrySet': countryCode,
        'language': language,
      });
      return http.get(uri).timeout(const Duration(seconds: 10));
    }

    try {
      var res = await doRequest();
      if (res.statusCode == 429) {
        // Kısa bir bekleme sonrası tek seferlik yeniden dene — burst
        // sırasında ara sıra 429 gelebilir, adresin tamamen kaybolmasındansa
        // bir kez daha denemek daha doğru.
        await Future.delayed(const Duration(seconds: 1));
        res = await doRequest();
      }
      if (res.statusCode != 200) return [];

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final results = decoded['results'] as List? ?? [];

      return results
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
    } catch (_) {
      return [];
    }
  }
}
