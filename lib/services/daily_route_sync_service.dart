import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/models/address.dart';
import '../data/address_store.dart';
import '../models/calendar_event.dart';
import '../models/vehicle_workspace.dart';
import 'auth_service.dart';
import 'osrm_route_service.dart';

/// Takvimde o gün için planlanmış duraklar varsa, bunları sürücünün aktif
/// rotasına (POST /routes) otomatik dönüştürür.
///
/// Önceden takvime adres eklemek sadece "planByDay" içinde kalıyordu;
/// sürücünün telefonda gördüğü aktif rota tamamen ayrı bir kavramdı ve
/// sadece ana panelden elle "Rota Oluştur" ile oluşuyordu. Artık takvim
/// planı ile aktif rota otomatik senkronize ediliyor — kullanıcının elle
/// tetiklemesine gerek yok.
///
/// Sıra, takvimde zaten (drag&drop / _optimizeShiftForDay ile) düzenlenmiş
/// sırayla birebir kullanılır — burada yeniden optimize edilmez, sadece
/// toplam süre/mesafe bilgisi için OSRM'den gerçek değerler çekilir.
Future<void> syncTodayRouteForDriver({
  required int driverId,
  required VehicleWorkspace workspace,
  OsrmRouteService osrm = const OsrmRouteService(),
}) async {
  final home = workspace.fixedHomeAddress;
  if (home == null || home.lat == null || home.lng == null) return;

  final now = DateTime.now();
  final todayKey = DateTime(now.year, now.month, now.day);
  final dayPlan = workspace.planByDay[todayKey];
  if (dayPlan == null) return;

  final items = <VisitPlanItem>[
    ...(dayPlan[ShiftType.morning] ?? const <VisitPlanItem>[]),
    ...(dayPlan[ShiftType.afternoon] ?? const <VisitPlanItem>[]),
  ];
  if (items.isEmpty) return;

  final byTitle = {for (final a in AddressStore.items) a.address: a};
  final stops = <Address>[];
  for (final item in items) {
    final a = byTitle[item.title];
    if (a != null && a.lat != null && a.lng != null) stops.add(a);
  }
  if (stops.isEmpty) return;

  try {
    // Kapalı tur: ev -> takvimdeki sıradaki duraklar -> ev.
    final nodes = <Address>[home, ...stops, home];
    final matrix = await osrm.table(
      coords: nodes.map((a) => LatLng(a.lat!, a.lng!)).toList(),
    );

    var totalMin = 0.0;
    var totalKm = 0.0;
    for (var i = 0; i < nodes.length - 1; i++) {
      totalMin += matrix.durationMin(i, i + 1) ?? 0;
      totalKm += matrix.distanceKm(i, i + 1) ?? 0;
    }

    final path = nodes.map((a) => a.address).toList();
    final stopsJson = nodes
        .asMap()
        .entries
        .map(
          (entry) => {
            'order': entry.key + 1,
            'code': entry.value.code,
            'address': entry.value.address,
            'street': entry.value.address,
            'customerName': entry.value.address,
            'latitude': entry.value.lat,
            'longitude': entry.value.lng,
            'notes': entry.value.note,
          },
        )
        .toList();

    await http.post(
      Uri.parse('https://route-backend-1.onrender.com/routes'),
      headers: await AuthService.authHeaders(),
      body: jsonEncode({
        'user_id': driverId,
        'name': 'Günlük Rota',
        'route_json': {
          'createdAt': now.toIso8601String(),
          'totalMin': totalMin.round(),
          'totalKm': double.parse(totalKm.toStringAsFixed(1)),
          'path': path,
          'stops': stopsJson,
        },
      }),
    );
  } catch (_) {
    // Ağ/OSRM hatası — sessizce geç, bir sonraki senkronizasyon
    // denemesinde (panel tekrar açıldığında ya da takvim düzenlenince)
    // tekrar denenir.
  }
}
