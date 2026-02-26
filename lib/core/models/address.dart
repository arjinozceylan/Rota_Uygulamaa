import 'dart:math' as math;

/// Uygulama genelinde kullanılacak Address modeli.
/// - placeId: (Google Place ID / OSM id vs.) dış kaynaktan gelen id
/// - lat/lng: koordinatlar (varsa) -> mesafe hesabı için
class Address {
  final String code; // ör: A001
  final String address; // ekranda görünen metin
  final String? note;

  /// Provider-specific id (Google Place ID, OSM id vb.)
  final String? placeId;

  /// Latitude (derece)
  final double? lat;

  /// Longitude (derece)
  final double? lng;

  const Address({
    required this.code,
    required this.address,
    this.note,
    this.placeId,
    this.lat,
    this.lng,
  });

  bool get hasCoordinates => lat != null && lng != null;

  Address copyWith({
    String? code,
    String? address,
    String? note,
    String? placeId,
    double? lat,
    double? lng,
  }) {
    return Address(
      code: code ?? this.code,
      address: address ?? this.address,
      note: note ?? this.note,
      placeId: placeId ?? this.placeId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  /// Kuş uçuşu mesafe (Haversine) -> metre cinsinden.
  /// NOT: Bu sürüş mesafesi/süresi değildir; ama “gerçekçi” bir metrik olarak
  /// rota algoritmasında heuristic/fallback olarak iş görür.
  double distanceMetersTo(Address other) {
    if (!hasCoordinates || !other.hasCoordinates) {
      throw StateError('Both addresses must have coordinates (lat/lng).');
    }
    return _haversineMeters(lat!, lng!, other.lat!, other.lng!);
  }

  double distanceKmTo(Address other) => distanceMetersTo(other) / 1000.0;

  Map<String, dynamic> toJson() => {
    'code': code,
    'address': address,
    'note': note,
    'placeId': placeId,
    'lat': lat,
    'lng': lng,
  };

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      code: (json['code'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      note: json['note']?.toString(),
      placeId: json['placeId']?.toString(),
      lat: (json['lat'] is num) ? (json['lat'] as num).toDouble() : null,
      lng: (json['lng'] is num) ? (json['lng'] as num).toDouble() : null,
    );
  }
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;

  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);

  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _degToRad(double deg) => deg * (math.pi / 180.0);
