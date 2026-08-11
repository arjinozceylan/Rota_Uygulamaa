import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/address.dart';
import '../data/address_store.dart';
import '../data/uploaded_files_store.dart';
import '../models/calendar_event.dart';
import '../models/vehicle_workspace.dart';
import '../services/reports_page.dart';
import '../services/auth_service.dart';

import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';

/// Uygulamanın kalıcı depolama servisi.
/// SharedPreferences kullanarak tüm verileri JSON olarak saklar.
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  /// Backend'e rota/filo senkronizasyonu başarısız olduğunda çağrılır.
  /// UI tarafı (ör. HomePage) bunu dinleyip kullanıcıya bir uyarı gösterebilir.
  void Function(String message)? onSyncError;

  static const _keyAddresses = 'addresses_v1';
  static const _keyRoutes = 'routes_v1';
  static const _keyUploads = 'uploads_v1';
  static const _keyFleet = 'fleet_v1';

  // ── KAYDET ────────────────────────────────────────────────────────────────

  Future<void> saveAll({
    required List<String> addressCards,
    required Map<int, VehicleWorkspace> fleet,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      _saveAddresses(prefs, addressCards),
      _saveRoutes(prefs),
      _saveUploads(prefs),
      _saveFleet(prefs, fleet),
    ]);
  }

  Future<void> saveAddresses(List<String> addressCards) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveAddresses(prefs, addressCards);
  }

  Future<void> saveRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveRoutes(prefs);
  }

  Future<void> saveFleet(Map<int, VehicleWorkspace> fleet) async {
    final prefs = await SharedPreferences.getInstance();
    await _saveFleet(prefs, fleet);
  }

  // ── YÜKlE ─────────────────────────────────────────────────────────────────

  Future<AppStorageData> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return AppStorageData(
      addressCards: _loadAddressCards(prefs),
      fleet: _loadFleet(prefs),
      routes: _loadRoutes(prefs),
      uploads: _loadUploads(prefs),
    );
  }

  // ── ADRESLER ──────────────────────────────────────────────────────────────

  Future<void> _saveAddresses(
    SharedPreferences prefs,
    List<String> addressCards,
  ) async {
    final addresses = AddressStore.items.map((a) => a.toJson()).toList();
    final data = jsonEncode({
      'addresses': addresses,
      'cards': addressCards,
    });
    await prefs.setString(_keyAddresses, data);
  }

  List<String> _loadAddressCards(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_keyAddresses);
      if (raw == null) return [];
      final data = jsonDecode(raw) as Map<String, dynamic>;

      // AddressStore'a yükle
      AddressStore.clear();
      final addresses = (data['addresses'] as List?)
              ?.map((e) => Address.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      for (final a in addresses) {
        AddressStore.add(a);
      }

      return List<String>.from(data['cards'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  // ── ROTALAR ───────────────────────────────────────────────────────────────

  Future<void> _saveRoutes(SharedPreferences prefs) async {
    // allRecords en yeniden en eskiye sıralı gelir (RouteStore.allRecords).
    final allRecords = RouteStore.instance.allRecords;

    final records = allRecords
        .map((r) => {
              'createdAt': r.createdAt.toIso8601String(),
              'totalMin': r.totalMin,
              'totalKm': r.totalKm,
              'path': r.path,
              'driverId': r.driverId,
            })
        .toList();

    // Önce eski sistem gibi local'e kaydet
    await prefs.setString(_keyRoutes, jsonEncode(records));

    // En son oluşturulan rotayı backend'e gönder (koordinatlı duraklarla).
    // Rota, oluşturulduğu sırada seçili olan SÜRÜCÜNÜN hesabına
    // (driverId — gerçek backend user_id'si) kaydedilir; admin'in kendi
    // hesabına değil. Mobil, kendi hesabının rotasını doğrudan
    // /routes/{kendi user_id'si}/active üzerinden çekiyor — artık ayrı bir
    // "araç" eşleşmesi yok, bu yüzden doğru driverId göndermek zorunlu.
    if (allRecords.isNotEmpty) {
      final lastRoute = allRecords.first;
      final driverId = lastRoute.driverId;
      if (driverId == null) return;

      final stops = lastRoute.stops ?? const <Address>[];
      final stopsJson = stops
          .asMap()
          .entries
          .map((entry) => {
                'order': entry.key + 1,
                'code': entry.value.code,
                'address': entry.value.address,
                'street': entry.value.address,
                'customerName': entry.value.address,
                'latitude': entry.value.lat,
                'longitude': entry.value.lng,
                'notes': entry.value.note,
              })
          .toList();

      try {
        final response = await http.post(
          Uri.parse("https://route-backend-1.onrender.com/routes"),
          headers: await AuthService.authHeaders(),
          body: jsonEncode({
            "user_id": driverId,
            "name": "Web Rota",
            "route_json": {
              "createdAt": lastRoute.createdAt.toIso8601String(),
              "totalMin": lastRoute.totalMin,
              "totalKm": lastRoute.totalKm,
              "path": lastRoute.path,
              "stops": stopsJson,
            },
          }),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          AuthService.flagIfSessionError(response.body);
          debugPrint(
            "Backend rota kaydetme hatası: ${response.statusCode} ${response.body}",
          );
          onSyncError?.call(
            "Rota sunucuya kaydedilemedi (${response.statusCode}). Mobil uygulama bu rotayı görmeyebilir.",
          );
        }
      } catch (e) {
        // Backend'e gönderilemezse web uygulaması bozulmasın, ama kullanıcıyı bilgilendir
        debugPrint("Backend rota kaydetme hatası: $e");
        onSyncError?.call(
          "Rota sunucuya kaydedilemedi. İnternet bağlantınızı kontrol edin.",
        );
      }
    }
  }

  List<RouteRecord> _loadRoutes(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_keyRoutes);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return RouteRecord(
          createdAt: DateTime.parse(m['createdAt'] as String),
          totalMin: m['totalMin'] as int,
          totalKm: (m['totalKm'] as num).toDouble(),
          path: List<String>.from(m['path'] as List),
          driverId: m['driverId'] as int?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── YÜKLENEN DOSYALAR ─────────────────────────────────────────────────────

  Future<void> saveUploads() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveUploads(prefs);
  }

  Future<void> _saveUploads(SharedPreferences prefs) async {
    final files = UploadedFilesStore.files
        .map((f) => {
              'fileName': f.fileName,
              'addressCount': f.addressCount,
              'uploadedAt': f.uploadedAt.toIso8601String(),
            })
        .toList();
    await prefs.setString(_keyUploads, jsonEncode(files));
  }

  List<UploadedFile> _loadUploads(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_keyUploads);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return UploadedFile(
          fileName: m['fileName'] as String,
          addressCount: m['addressCount'] as int,
          uploadedAt: DateTime.parse(m['uploadedAt'] as String),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── FLEET / ARAÇ STATE ────────────────────────────────────────────────────

  Timer? _fleetPushTimer;

  Future<void> _saveFleet(
    SharedPreferences prefs,
    Map<int, VehicleWorkspace> fleet,
  ) async {
    final data = <String, dynamic>{};
    for (final entry in fleet.entries) {
      final ws = entry.value;
      data[entry.key.toString()] = {
        'fixedHome': ws.fixedHomeAddress?.toJson(),
        'dropped': ws.dropped,
        'repeatByAddress': ws.repeatByAddress.map(
          (k, v) => MapEntry(k, v.index),
        ),
        // Takvim verisi (planByDay/forcedFirstStopByDay) daha önce hiç
        // kaydedilmiyordu — sekme kapatılıp açıldığında ya da .exe yeniden
        // başlatıldığında tüm planlanmış ziyaretler sessizce kayboluyordu.
        'planByDay': ws.planByDay.map(
          (day, shifts) => MapEntry(
            day.toIso8601String(),
            shifts.map(
              (shift, items) => MapEntry(
                shift.name,
                items.map((i) => i.toJson()).toList(),
              ),
            ),
          ),
        ),
        'forcedFirstStopByDay': ws.forcedFirstStopByDay.map(
          (day, shifts) => MapEntry(
            day.toIso8601String(),
            shifts.map((shift, title) => MapEntry(shift.name, title)),
          ),
        ),
      };
    }
    await prefs.setString(_keyFleet, jsonEncode(data));

    // Backend'e gönderimi 3sn debounce ederek art arda gelen aksiyonları
    // (adres ekle/sil vb.) tek istekte topla. Her sürücünün workspace'i
    // artık kendi gerçek user_id'siyle ayrı ayrı kaydediliyor — eskiden
    // tek bir "filo" bloğu tüm araçları (0-4) içeren tek bir istekte
    // gidiyordu; her sürücünün verisi artık gerçekten kendine özel.
    _fleetPushTimer?.cancel();
    _fleetPushTimer = Timer(const Duration(seconds: 3), () async {
      for (final entry in data.entries) {
        final driverId = entry.key;
        try {
          final response = await http.post(
            Uri.parse("https://route-backend-1.onrender.com/fleet/$driverId"),
            headers: await AuthService.authHeaders(),
            body: jsonEncode({"workspace": entry.value}),
          );

          if (response.statusCode < 200 || response.statusCode >= 300) {
            AuthService.flagIfSessionError(response.body);
            debugPrint(
              "Backend filo kaydetme hatası ($driverId): ${response.statusCode} ${response.body}",
            );
            onSyncError?.call(
              "Filo bilgisi sunucuya kaydedilemedi (${response.statusCode}).",
            );
          }
        } catch (e) {
          // Backend'e gönderilemezse web uygulaması bozulmasın, ama kullanıcıyı bilgilendir
          debugPrint("Backend filo kaydetme hatası ($driverId): $e");
          onSyncError?.call("Filo bilgisi sunucuya kaydedilemedi.");
        }
      }
    });
  }

  Map<int, VehicleWorkspace> _loadFleet(SharedPreferences prefs) {
    final fleet = <int, VehicleWorkspace>{};
    try {
      final raw = prefs.getString(_keyFleet);
      if (raw == null) return fleet;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      for (final entry in data.entries) {
        final driverId = int.tryParse(entry.key);
        if (driverId == null) continue;
        final m = entry.value as Map<String, dynamic>;

        Address? fixedHome;
        if (m['fixedHome'] != null) {
          fixedHome = Address.fromJson(m['fixedHome'] as Map<String, dynamic>);
        }

        final dropped = List<String>.from(m['dropped'] as List? ?? []);

        final repeatRaw = m['repeatByAddress'] as Map<String, dynamic>? ?? {};
        final repeatByAddress = repeatRaw.map(
          (k, v) => MapEntry(k, RepeatType.values[v as int]),
        );

        final planByDayRaw = m['planByDay'] as Map<String, dynamic>? ?? {};
        final planByDay = <DateTime, Map<ShiftType, List<VisitPlanItem>>>{};
        for (final dayEntry in planByDayRaw.entries) {
          final day = DateTime.parse(dayEntry.key);
          final shiftsRaw = dayEntry.value as Map<String, dynamic>;
          planByDay[day] = shiftsRaw.map(
            (shiftName, itemsRaw) => MapEntry(
              ShiftType.values.byName(shiftName),
              (itemsRaw as List)
                  .map((e) => VisitPlanItem.fromJson(e as Map<String, dynamic>))
                  .toList(),
            ),
          );
        }

        final forcedRaw =
            m['forcedFirstStopByDay'] as Map<String, dynamic>? ?? {};
        final forcedFirstStopByDay = <DateTime, Map<ShiftType, String?>>{};
        for (final dayEntry in forcedRaw.entries) {
          final day = DateTime.parse(dayEntry.key);
          final shiftsRaw = dayEntry.value as Map<String, dynamic>;
          forcedFirstStopByDay[day] = shiftsRaw.map(
            (shiftName, title) =>
                MapEntry(ShiftType.values.byName(shiftName), title as String?),
          );
        }

        // Kullanıcı adı burada bilinmiyor (yerel önbellek sadece id
        // tutuyor) — geçici bir etiket kullanılır, FleetState.syncDrivers
        // backend'den gelen gerçek sürücü listesiyle bunu hemen düzeltir.
        fleet[driverId] = VehicleWorkspace(
          driver: Driver(id: driverId, username: 'Sürücü $driverId'),
          fixedHomeAddress: fixedHome,
          dropped: dropped,
          repeatByAddress: repeatByAddress,
          planByDay: planByDay,
          forcedFirstStopByDay: forcedFirstStopByDay,
        );
      }
    } catch (_) {}
    return fleet;
  }
}

class AppStorageData {
  final List<String> addressCards;
  final Map<int, VehicleWorkspace> fleet;
  final List<RouteRecord> routes;
  final List<UploadedFile> uploads;

  const AppStorageData({
    required this.addressCards,
    required this.fleet,
    required this.routes,
    required this.uploads,
  });
}
