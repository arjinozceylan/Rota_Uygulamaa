import '../core/models/address.dart';
import 'calendar_event.dart';

/// Backend'deki bir sürücü hesabının web panelindeki karşılığı.
///
/// Önceden burada sabit 5 "araç" slotu vardı ve her birine ayrıca bir
/// sürücü atanıyordu; mobil uygulama zaten her zaman doğrudan sürücünün
/// kendi hesabı üzerinden çalıştığı için bu ekstra katman kaldırıldı —
/// artık web panelindeki sekmelerin her biri doğrudan bir sürücüyü temsil
/// eder.
class Driver {
  const Driver({required this.id, required this.username});

  final int id;
  final String username;

  String get label => username;

  @override
  bool operator ==(Object other) => other is Driver && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Tek bir sürücünün çalışma alanı / state'i.
///
/// Ortak adres havuzu bu modelin DIŞINDA kalır.
/// Bu model sadece sürücü bazlı tutulması gereken verileri içerir.
class VehicleWorkspace {
  VehicleWorkspace({
    required this.driver,
    this.fixedHomeAddress,
    List<String>? dropped,
    Map<String, RepeatType>? repeatByAddress,
    Map<DateTime, Map<ShiftType, List<VisitPlanItem>>>? planByDay,
    Map<DateTime, Map<ShiftType, String?>>? forcedFirstStopByDay,
  }) : dropped = dropped ?? <String>[],
       repeatByAddress = repeatByAddress ?? <String, RepeatType>{},
       planByDay = planByDay ?? <DateTime, Map<ShiftType, List<VisitPlanItem>>>{},
       forcedFirstStopByDay =
           forcedFirstStopByDay ?? <DateTime, Map<ShiftType, String?>>{};

  final Driver driver;

  int get driverId => driver.id;

  /// Sabit ev / başlangıç / bitiş noktası
  Address? fixedHomeAddress;

  /// HomePage sağ panelindeki rota kuyruğu
  final List<String> dropped;

  /// Adrese bağlı tekrar tipi bilgisi
  final Map<String, RepeatType> repeatByAddress;

  /// Takvim verisi: Gün -> Vardiya -> Ziyaret listesi
  final Map<DateTime, Map<ShiftType, List<VisitPlanItem>>> planByDay;

  /// Kullanıcı bir vardiyada bir adresi en üste sürüklediyse,
  /// HOME'dan sonraki zorunlu ilk durak olarak tutulur.
  final Map<DateTime, Map<ShiftType, String?>> forcedFirstStopByDay;

  bool get hasFixedHome =>
      fixedHomeAddress != null &&
      fixedHomeAddress!.lat != null &&
      fixedHomeAddress!.lng != null;

  /// UI'da kolay kullanım için güvenli kopya üretir.
  VehicleWorkspace copy() {
    return VehicleWorkspace(
      driver: driver,
      fixedHomeAddress: fixedHomeAddress,
      dropped: List<String>.from(dropped),
      repeatByAddress: Map<String, RepeatType>.from(repeatByAddress),
      planByDay: {
        for (final entry in planByDay.entries)
          entry.key: {
            for (final shiftEntry in entry.value.entries)
              shiftEntry.key: List<VisitPlanItem>.from(shiftEntry.value),
          },
      },
      forcedFirstStopByDay: {
        for (final entry in forcedFirstStopByDay.entries)
          entry.key: Map<ShiftType, String?>.from(entry.value),
      },
    );
  }
}
