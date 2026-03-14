

import 'package:flutter/material.dart';

import '../core/models/address.dart';
import 'calendar_event.dart';

/// Uygulamadaki 5 araç için sabit kimlikler.
///
/// İleride UI'da buton / sekme / chip olarak göstereceğiz.
enum VehicleId {
  vehicle1,
  vehicle2,
  vehicle3,
  vehicle4,
  vehicle5,
}

extension VehicleIdX on VehicleId {
  String get label {
    switch (this) {
      case VehicleId.vehicle1:
        return 'Araç 1';
      case VehicleId.vehicle2:
        return 'Araç 2';
      case VehicleId.vehicle3:
        return 'Araç 3';
      case VehicleId.vehicle4:
        return 'Araç 4';
      case VehicleId.vehicle5:
        return 'Araç 5';
    }
  }
}

/// Tek bir aracın çalışma alanı / state'i.
///
/// Ortak adres havuzu bu modelin DIŞINDA kalır.
/// Bu model sadece araç bazlı tutulması gereken verileri içerir.
class VehicleWorkspace {
  VehicleWorkspace({
    required this.id,
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

  final VehicleId id;

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
      id: id,
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

  /// Fabrika: 5 aracın başlangıç workspace'lerini üretmek için kullanışlı.
  static Map<VehicleId, VehicleWorkspace> createInitialFleet() {
    return {
      for (final id in VehicleId.values) id: VehicleWorkspace(id: id),
    };
  }
}