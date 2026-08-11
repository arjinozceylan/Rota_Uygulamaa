import 'package:flutter/foundation.dart';

import '../models/vehicle_workspace.dart';

/// Uygulamanın sürücü bazlı merkezi state'i.
///
/// Amaç:
/// - Her sürücü için ayrı çalışma alanı tutmak
/// - Aktif sürücüyü değiştirebilmek
/// - UI tarafında aktif sürücüye göre Home/Calendar/Reports verisi göstermek
///
/// Sürücü listesi backend'den (/users/drivers) dinamik olarak gelir —
/// sabit bir sayı (eskiden 5 "araç") yoktur.
class FleetState extends ChangeNotifier {
  /// [initialFleet]: cihazda önceden önbelleğe alınmış sürücü çalışma
  /// alanları (bkz. AppStorage._loadFleet). Backend'den güncel sürücü
  /// listesi henüz gelmediği için başlangıçta hangi id'lerin hâlâ geçerli
  /// olduğu bilinmez — [syncDrivers] çağrıldığında artık var olmayan
  /// sürücülerin verisi otomatik temizlenir, var olanlarınki korunur.
  FleetState({Map<int, VehicleWorkspace>? initialFleet})
    : _fleet = initialFleet ?? {};

  final Map<int, VehicleWorkspace> _fleet;
  int? _activeDriverId;

  /// Şu an UI'da seçili olan sürücünün id'si (henüz sürücü listesi
  /// yüklenmediyse null).
  int? get activeDriverId => _activeDriverId;

  /// Sürücü listesinin (backend'den gelen sırayla) read-only görünümü.
  List<Driver> get drivers =>
      _fleet.values.map((ws) => ws.driver).toList(growable: false);

  /// Aktif sürücünün tüm workspace verisi.
  VehicleWorkspace? get activeWorkspace =>
      _activeDriverId == null ? null : _fleet[_activeDriverId];

  /// Tüm sürücülerin read-only görünümü
  Map<int, VehicleWorkspace> get fleetView => Map.unmodifiable(_fleet);

  /// Backend'den gelen güncel sürücü listesiyle senkronize eder.
  /// Zaten var olan sürücülerin workspace verisi korunur; yeni sürücüler
  /// boş bir workspace ile eklenir. Artık listede olmayan (silinmiş)
  /// sürücüler kaldırılır.
  void syncDrivers(List<Driver> newDrivers) {
    final newIds = newDrivers.map((d) => d.id).toSet();
    _fleet.removeWhere((id, _) => !newIds.contains(id));
    for (final driver in newDrivers) {
      final existing = _fleet[driver.id];
      if (existing == null) {
        _fleet[driver.id] = VehicleWorkspace(driver: driver);
      } else {
        // Yerel önbellekten gelen girdinin Driver'ı (ör. kullanıcı adı)
        // eski/placeholder olabilir — geri kalan veriyi koruyup Driver'ı
        // backend'den az önce gelen güncel değerle değiştir.
        _fleet[driver.id] = VehicleWorkspace(
          driver: driver,
          fixedHomeAddress: existing.fixedHomeAddress,
          dropped: existing.dropped,
          repeatByAddress: existing.repeatByAddress,
          planByDay: existing.planByDay,
          forcedFirstStopByDay: existing.forcedFirstStopByDay,
        );
      }
    }
    if (_activeDriverId == null || !newIds.contains(_activeDriverId)) {
      _activeDriverId = newDrivers.isEmpty ? null : newDrivers.first.id;
    }
    notifyListeners();
  }

  /// Yerel depodan yüklenen workspace verisini ilgili sürücüye uygular.
  /// Sürücü henüz [syncDrivers] ile tanınmıyorsa (backend'den liste daha
  /// gelmediyse) veri geçici bir girdi olarak tutulur.
  void hydrateWorkspace(int driverId, VehicleWorkspace workspace) {
    _fleet[driverId] = workspace;
    notifyListeners();
  }

  /// Belirli bir sürücüyü seç
  void selectDriver(int driverId) {
    if (_activeDriverId == driverId) return;
    if (!_fleet.containsKey(driverId)) return;
    _activeDriverId = driverId;
    notifyListeners();
  }

  /// Belirli bir sürücünün workspace'ine eriş
  VehicleWorkspace? workspaceOf(int driverId) => _fleet[driverId];

  /// Aktif sürücünün workspace'ini güncellemek için güvenli yardımcı.
  ///
  /// Not:
  /// VehicleWorkspace mutable bir model olduğu için,
  /// callback içinde doğrudan alanlar güncellenebilir.
  /// Sonunda notifyListeners çağrılır.
  void updateActiveWorkspace(void Function(VehicleWorkspace workspace) update) {
    final ws = activeWorkspace;
    if (ws == null) return;
    update(ws);
    notifyListeners();
  }

  /// Belirli bir sürücüyü güncelle
  void updateWorkspace(
    int driverId,
    void Function(VehicleWorkspace workspace) update,
  ) {
    final ws = _fleet[driverId];
    if (ws == null) return;
    update(ws);
    notifyListeners();
  }

  /// Tek bir sürücünün verisini sıfırla (ortak adres havuzu hariç)
  void resetDriver(int driverId) {
    final existing = _fleet[driverId];
    if (existing == null) return;
    _fleet[driverId] = VehicleWorkspace(driver: existing.driver);
    notifyListeners();
  }

  /// Calendar veya workspace içinde veri değiştiğinde UI'ı güncellemek için kullanılır
  void markDirty() {
    notifyListeners();
  }
}
