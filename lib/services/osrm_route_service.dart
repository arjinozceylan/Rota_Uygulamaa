import 'dart:convert';
import 'package:http/http.dart' as http;

/// OSRM demo server kullanır.
/// Not: Demo server yoğun olursa hata verebilir.
class OsrmRouteService {
  const OsrmRouteService();

  static const String _base = 'https://router.project-osrm.org';

  /// OSRM Table: NxN duration & distance matrix
  /// coords: list of (lat,lng)
  Future<OsrmMatrix> table({required List<LatLng> coords}) async {
    if (coords.length < 2) {
      throw Exception('OSRM table needs at least 2 coordinates');
    }

    // OSRM expects: lng,lat;lng,lat;...
    final coordStr = coords
        .map((c) => '${c.lng.toStringAsFixed(6)},${c.lat.toStringAsFixed(6)}')
        .join(';');

    final uri = Uri.parse(
      '$_base/table/v1/driving/$coordStr'
      '?annotations=duration,distance',
    );

    final res = await http.get(
      uri,
      headers: const {'User-Agent': 'RotaUygulamaa/1.0'},
    );

    if (res.statusCode != 200) {
      throw Exception('OSRM table failed: ${res.statusCode} ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;

    final durationsRaw = (json['durations'] as List).cast<List>();
    final distancesRaw = (json['distances'] as List).cast<List>();

    final durations = durationsRaw
        .map(
          (row) =>
              row.map((v) => v == null ? null : (v as num).toDouble()).toList(),
        )
        .toList();

    final distances = distancesRaw
        .map(
          (row) =>
              row.map((v) => v == null ? null : (v as num).toDouble()).toList(),
        )
        .toList();

    return OsrmMatrix(durationsSeconds: durations, distancesMeters: distances);
  }
}

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class OsrmMatrix {
  const OsrmMatrix({
    required this.durationsSeconds,
    required this.distancesMeters,
  });

  /// [i][j] = i -> j seconds (null olabilir)
  final List<List<double?>> durationsSeconds;

  /// [i][j] = i -> j meters (null olabilir)
  final List<List<double?>> distancesMeters;

  int get n => durationsSeconds.length;

  double? durationMin(int i, int j) =>
      durationsSeconds[i][j] == null ? null : durationsSeconds[i][j]! / 60.0;

  double? distanceKm(int i, int j) =>
      distancesMeters[i][j] == null ? null : distancesMeters[i][j]! / 1000.0;
}
