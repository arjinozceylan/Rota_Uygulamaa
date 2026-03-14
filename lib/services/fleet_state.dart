import 'package:flutter/foundation.dart';

import '../models/vehicle_workspace.dart';

/// Uygulamanın araç bazlı merkezi state'i.
///
/// Amaç:
/// - 5 aracın her biri için ayrı çalışma alanı tutmak
/// - aktif aracı değiştirebilmek
/// - UI tarafında aktif araca göre Home/Calendar/Reports verisi göstermek
class FleetState extends ChangeNotifier {
  FleetState({
    Map<VehicleId, VehicleWorkspace>? fleet,
    VehicleId initialVehicle = VehicleId.vehicle1,
  }) : _fleet = fleet ?? VehicleWorkspace.createInitialFleet(),
       _activeVehicle = initialVehicle;

  final Map<VehicleId, VehicleWorkspace> _fleet;
  VehicleId _activeVehicle;

  /// Şu an UI'da seçili olan araç
  VehicleId get activeVehicle => _activeVehicle;

  /// Aktif aracın tüm workspace verisi
  VehicleWorkspace get activeWorkspace => _fleet[_activeVehicle]!;

  /// Tüm araçların read-only görünümü
  Map<VehicleId, VehicleWorkspace> get fleetView => Map.unmodifiable(_fleet);

  /// Belirli bir aracı seç
  void selectVehicle(VehicleId id) {
    if (_activeVehicle == id) return;
    _activeVehicle = id;
    notifyListeners();
  }

  /// Belirli bir aracın workspace'ine eriş
  VehicleWorkspace workspaceOf(VehicleId id) => _fleet[id]!;

  /// Aktif aracın workspace'ini güncellemek için güvenli yardımcı.
  ///
  /// Not:
  /// VehicleWorkspace mutable bir model olduğu için,
  /// callback içinde doğrudan alanlar güncellenebilir.
  /// Sonunda notifyListeners çağrılır.
  void updateActiveWorkspace(void Function(VehicleWorkspace workspace) update) {
    final ws = activeWorkspace;
    update(ws);
    notifyListeners();
  }

  /// Belirli bir aracı güncelle
  void updateWorkspace(
    VehicleId id,
    void Function(VehicleWorkspace workspace) update,
  ) {
    final ws = _fleet[id]!;
    update(ws);
    notifyListeners();
  }

  /// Tüm araç verilerini sıfırla (ortak address havuzu hariç)
  void resetAllVehicles() {
    _fleet
      ..clear()
      ..addAll(VehicleWorkspace.createInitialFleet());
    _activeVehicle = VehicleId.vehicle1;
    notifyListeners();
  }

  /// Tek bir aracı sıfırla
  void resetVehicle(VehicleId id) {
    _fleet[id] = VehicleWorkspace(id: id);
    notifyListeners();
  }

  /// Calendar veya workspace içinde veri değiştiğinde UI'ı güncellemek için kullanılır
  void markDirty() {
    notifyListeners();
  }
}
