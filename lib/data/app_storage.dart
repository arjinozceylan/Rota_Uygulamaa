import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/address.dart';
import '../data/address_store.dart';
import '../data/uploaded_files_store.dart';
import '../models/calendar_event.dart';
import '../models/vehicle_workspace.dart';
import '../services/reports_page.dart';

/// Uygulamanın kalıcı depolama servisi.
/// SharedPreferences kullanarak tüm verileri JSON olarak saklar.
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

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
          .toList() ?? [];
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
    final records = RouteStore.instance.allRecords.map((r) => {
      'createdAt': r.createdAt.toIso8601String(),
      'totalMin': r.totalMin,
      'totalKm': r.totalKm,
      'path': r.path,
      'vehicleId': r.vehicleId?.index,
    }).toList();
    await prefs.setString(_keyRoutes, jsonEncode(records));
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
    final files = UploadedFilesStore.files.map((f) => {
      'fileName': f.fileName,
      'addressCount': f.addressCount,
      'uploadedAt': f.uploadedAt.toIso8601String(),
    }).toList();
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