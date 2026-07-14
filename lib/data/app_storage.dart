import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/address.dart';
import '../data/address_store.dart';
import '../data/uploaded_files_store.dart';
import '../models/calendar_event.dart';
import '../models/vehicle_workspace.dart';
import '../services/reports_page.dart';

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
    required Map<VehicleId, VehicleWorkspace> fleet,
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

  Future<void> saveFleet(Map<VehicleId, VehicleWorkspace> fleet) async {
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
              'vehicleId': r.vehicleId?.index,
            })
        .toList();

    // Önce eski sistem gibi local'e kaydet
    await prefs.setString(_keyRoutes, jsonEncode(records));

    // En son oluşturulan rotayı backend'e gönder (koordinatlı duraklarla)
    if (allRecords.isNotEmpty) {
      final lastRoute = allRecords.first;
      final userId = prefs.getInt("user_id") ?? 1;

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
          Uri.parse("https://route-backend-jeu7.onrender.com/routes"),
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "user_id": userId,
            "vehicle_id": lastRoute.vehicleId?.index,
            "name": "Web Rota",
            "route_json": {
              "createdAt": lastRoute.createdAt.toIso8601String(),
              "totalMin": lastRoute.totalMin,
              "totalKm": lastRoute.totalKm,
              "path": lastRoute.path,
              "stops": stopsJson,
              "vehicleId": lastRoute.vehicleId?.index,
            },
          }),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
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
        final vidx = m['vehicleId'] as int?;
        return RouteRecord(
          createdAt: DateTime.parse(m['createdAt'] as String),
          totalMin: m['totalMin'] as int,
          totalKm: (m['totalKm'] as num).toDouble(),
          path: List<String>.from(m['path'] as List),
          vehicleId: vidx != null ? VehicleId.values[vidx] : null,
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
    Map<VehicleId, VehicleWorkspace> fleet,
  ) async {
    final data = <String, dynamic>{};
    for (final entry in fleet.entries) {
      final ws = entry.value;
      data[entry.key.index.toString()] = {
        'fixedHome': ws.fixedHomeAddress?.toJson(),
        'dropped': ws.dropped,
        'repeatByAddress': ws.repeatByAddress.map(
          (k, v) => MapEntry(k, v.index),
        ),
      };
    }
    await prefs.setString(_keyFleet, jsonEncode(data));

    // Backend'e gönderimi 3sn debounce ederek art arda gelen aksiyonları
    // (adres ekle/sil vb.) tek istekte topla.
    final userId = prefs.getInt("user_id") ?? 1;
    _fleetPushTimer?.cancel();
    _fleetPushTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final response = await http.post(
          Uri.parse("https://route-backend-jeu7.onrender.com/fleet/$userId"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"vehicles": data}),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            "Backend filo kaydetme hatası: ${response.statusCode} ${response.body}",
          );
          onSyncError?.call(
            "Filo bilgisi sunucuya kaydedilemedi (${response.statusCode}).",
          );
        }
      } catch (e) {
        // Backend'e gönderilemezse web uygulaması bozulmasın, ama kullanıcıyı bilgilendir
        debugPrint("Backend filo kaydetme hatası: $e");
        onSyncError?.call("Filo bilgisi sunucuya kaydedilemedi.");
      }
    });
  }

  Map<VehicleId, VehicleWorkspace> _loadFleet(SharedPreferences prefs) {
    final fleet = VehicleWorkspace.createInitialFleet();
    try {
      final raw = prefs.getString(_keyFleet);
      if (raw == null) return fleet;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      for (final entry in data.entries) {
        final idx = int.tryParse(entry.key);
        if (idx == null || idx >= VehicleId.values.length) continue;
        final vid = VehicleId.values[idx];
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

        fleet[vid] = VehicleWorkspace(
          id: vid,
          fixedHomeAddress: fixedHome,
          dropped: dropped,
          repeatByAddress: repeatByAddress,
        );
      }
    } catch (_) {}
    return fleet;
  }
}

class AppStorageData {
  final List<String> addressCards;
  final Map<VehicleId, VehicleWorkspace> fleet;
  final List<RouteRecord> routes;
  final List<UploadedFile> uploads;

  const AppStorageData({
    required this.addressCards,
    required this.fleet,
    required this.routes,
    required this.uploads,
  });
}
