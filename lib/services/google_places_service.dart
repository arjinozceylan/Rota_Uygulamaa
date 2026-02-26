import 'dart:convert';

import 'package:http/http.dart' as http;

class GooglePlacesService {
  const GooglePlacesService();

  static const _apiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  bool get hasApiKey => _apiKey.isNotEmpty;

  Future<List<String>> autocomplete({
    required String input,
    String language = 'tr',
    String countryCode = 'tr',
    int limit = 5,
  }) async {
    if (_apiKey.isEmpty) return [];

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
          'input': input,
          'types': 'address',
          'language': language,
          'components': 'country:$countryCode',
          'key': _apiKey,
        });

    final response = await http.get(uri);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') return [];

    final predictions =
        (data['predictions'] as List<dynamic>? ?? const <dynamic>[]);
    return predictions
        .map((item) => (item as Map<String, dynamic>)['description'] as String?)
        .whereType<String>()
        .take(limit)
        .toList();
  }
}
