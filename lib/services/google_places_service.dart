import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models/address.dart';

/// OpenStreetMap / Nominatim based search service.
///
/// Bu servis Google Places Autocomplete yerine kullanılır (gerçek adres seçimi).
///
/// Önemli:
/// - Nominatim public servisinde spam yapma (debounce şart).
/// - Yaklaşık 1 istek/saniye üstüne çıkma.
/// - User-Agent header zorunlu.
class GooglePlacesService {
  const GooglePlacesService();

  static const _base = 'nominatim.openstreetmap.org';

  /// OSM public endpoint için API key yok, bu yüzden true.
  bool get hasApiKey => true;

  /// Nominatim üzerinden adres adaylarını getirir.
  ///
  /// [input] kullanıcının yazdığı metin
  /// [countryCode] ile kısıtlayabilirsin (örn: "tr")
  Future<List<Address>> autocomplete({
    required String input,
    String language = 'tr',
    String countryCode = 'tr',
    int limit = 5,
  }) async {
    final q = input.trim();
    if (q.isEmpty) return [];

    final uri = Uri.https(_base, '/search', {
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': limit.toString(),
      'countrycodes': countryCode,
      'accept-language': language,
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'rota_uygulamasi/1.0 (contact: dev@local)',
        'Accept-Language': language,
      },
    );

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as List<dynamic>;

    int codeCounter = 1;

    return data
        .map((e) {
          final m = e as Map<String, dynamic>;

          final osmType = m['osm_type']?.toString() ?? 'osm';
          final osmId =
              m['osm_id']?.toString() ?? m['place_id']?.toString() ?? '';
          final id = '$osmType:$osmId';

          final label = m['display_name']?.toString() ?? '';

          final latStr = m['lat']?.toString();
          final lonStr = m['lon']?.toString();

          final lat = latStr == null ? null : double.tryParse(latStr);
          final lng = lonStr == null ? null : double.tryParse(lonStr);

          final code = 'A${codeCounter.toString().padLeft(3, '0')}';
          codeCounter++;

          return Address(
            code: code,
            address: label,
            placeId: id,
            lat: lat,
            lng: lng,
          );
        })
        .where((a) => a.address.trim().isNotEmpty)
        .toList();
  }
}
