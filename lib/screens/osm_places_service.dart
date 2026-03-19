import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/models/address.dart';

/// OpenStreetMap / Nominatim ile adres arama servisi.
/// Amaç: gerçek adres + lat/lng almak (yol tarifi değil).
///
/// Notlar:
/// - Public Nominatim için spam yapma: UI'da debounce kullan (>=400ms).
/// - User-Agent zorunlu. Aksi halde bloklanabilir.
class OsmPlacesService {
  const OsmPlacesService();

  static const String _host = 'nominatim.openstreetmap.org';

  /// [query]: kullanıcının yazdığı metin
  /// [limit]: kaç öneri dönecek
  /// [countryCode]: 'tr' gibi ülke filtresi
  Future<List<Address>> search({
    required String query,
    int limit = 6,
    String countryCode = 'tr',
    String language = 'tr',
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.https(_host, '/search', {
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': limit.toString(),
      'countrycodes': countryCode,
      'accept-language': language,
    });

    final res = await http.get(
      uri,
      headers: {
        'User-Agent': 'RotaUygulamaa/1.0 (local-dev)',
        'Accept-Language': language,
      },
    );

    if (res.statusCode != 200) {
      return [];
    }

    final List data = jsonDecode(res.body) as List;

    int i = 1;
    return data
        .map((e) => e as Map<String, dynamic>)
        .map((m) {
          final display = (m['display_name'] ?? '').toString();
          final lat = double.tryParse((m['lat'] ?? '').toString());
          final lon = double.tryParse((m['lon'] ?? '').toString());

          // Nominatim: osm_type + osm_id ile stabil id
          final osmType = (m['osm_type'] ?? 'osm').toString();
          final osmId = (m['osm_id'] ?? m['place_id'] ?? '').toString();
          final placeId = '$osmType:$osmId';

          // code: sadece local label (istersen kaldırabilirsin)
          final code = 'OSM${i.toString().padLeft(3, '0')}';
          i++;

          return Address(
            code: code,
            address: display,
            placeId: placeId,
            lat: lat,
            lng: lon,
          );
        })
        .where(
          (a) => a.address.trim().isNotEmpty && a.lat != null && a.lng != null,
        )
        .toList();
  }

  /// Koordinattan adres bul (reverse geocoding)
  Future<Address?> reverseGeocode({
    required double lat,
    required double lng,
    String language = 'tr',
  }) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': lat.toString(),
      'lon': lng.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'accept-language': language,
    });

    try {
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'RotaUygulamaa/1.0 (local-dev)',
          'Accept-Language': language,
        },
      );

      if (res.statusCode != 200) return null;

      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final display = (m['display_name'] ?? '').toString();
      if (display.isEmpty) return null;

      final osmType = (m['osm_type'] ?? 'osm').toString();
      final osmId = (m['osm_id'] ?? m['place_id'] ?? '').toString();
      final placeId = '\$osmType:\$osmId';

      return Address(
        code: 'C001',
        address: display,
        placeId: placeId,
        lat: lat,
        lng: lng,
      );
    } catch (e) {
      return null;
    }
  }
}