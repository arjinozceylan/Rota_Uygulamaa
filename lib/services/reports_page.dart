import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vehicle_workspace.dart';
import '../services/fleet_state.dart';

enum _ReportTarget { all, vehicle1, vehicle2, vehicle3, vehicle4, vehicle5 }

// ─────────────────────────────────────────────────────────────────────────────
// MODEL — Rota Kaydı
// ─────────────────────────────────────────────────────────────────────────────
class RouteRecord {
  final DateTime createdAt;
  final int totalMin;
  final double totalKm;
  final List<String> path; // sıralı adres listesi
  final VehicleId? vehicleId;

  const RouteRecord({
    required this.createdAt,
    required this.totalMin,
    required this.totalKm,
    required this.path,
    this.vehicleId,
  });

  int get stopCount => path.length - 1;
}

class ReportDataset {
  const ReportDataset(this.records);

  final List<RouteRecord> records;

  int get totalRoutes => records.length;

  int get totalTransfers => records.fold(0, (s, r) => s + r.stopCount);

  double get totalKm => records.fold(0.0, (s, r) => s + r.totalKm);

  int get totalMin => records.fold(0, (s, r) => s + r.totalMin);

  double get avgKm => records.isEmpty ? 0 : totalKm / records.length;

  int get avgMin => records.isEmpty ? 0 : totalMin ~/ records.length;

  Map<String, int> get addressFrequency {
    final map = <String, int>{};
    for (final r in records) {
      for (final addr in r.path) {
        map[addr] = (map[addr] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Map<String, List<RouteRecord>> get byWeek {
    final map = <String, List<RouteRecord>>{};
    for (final r in records) {
      final mon = r.createdAt.subtract(Duration(days: r.createdAt.weekday - 1));
      final key = '${mon.day}/${mon.month}/${mon.year}';
      map.putIfAbsent(key, () => []).add(r);
    }
    return map;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IN-MEMORY STORE — singleton, uygulama açık olduğu sürece tutar
// ─────────────────────────────────────────────────────────────────────────────
class RouteStore {
  RouteStore._();
  static final RouteStore instance = RouteStore._();

  final List<RouteRecord> _legacyRecords = [];
  final Map<VehicleId, List<RouteRecord>> _vehicleRecords = {
    for (final id in VehicleId.values) id: <RouteRecord>[],
  };

  /// Geriye uyumluluk: tüm kayıtların birleşik görünümü
  List<RouteRecord> get records => allRecords;

  List<RouteRecord> get allRecords {
    return [
      ..._legacyRecords,
      for (final id in VehicleId.values) ..._vehicleRecords[id]!,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<RouteRecord> recordsForVehicle(VehicleId id) {
    return List<RouteRecord>.from(_vehicleRecords[id]!)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  ReportDataset datasetForTarget(_ReportTarget target) {
    if (target == _ReportTarget.all) {
      return ReportDataset(allRecords);
    }
    return ReportDataset(recordsForVehicle(_vehicleFromTargetStatic(target)));
  }

  bool _isDuplicate(RouteRecord r, List<RouteRecord> list) {
    return list.any((existing) =>
        existing.path.length == r.path.length &&
        existing.totalMin == r.totalMin &&
        existing.totalKm.toStringAsFixed(1) == r.totalKm.toStringAsFixed(1) &&
        List.generate(existing.path.length, (i) => existing.path[i] == r.path[i])
            .every((same) => same));
  }

  void add(RouteRecord r) {
    if (r.vehicleId == null) {
      if (!_isDuplicate(r, _legacyRecords)) {
        _legacyRecords.insert(0, r);
      }
      return;
    }
    final list = _vehicleRecords[r.vehicleId!]!;
    if (!_isDuplicate(r, list)) {
      list.insert(0, r);
    }
  }

  void clear() {
    _legacyRecords.clear();
    for (final id in VehicleId.values) {
      _vehicleRecords[id]!.clear();
    }
  }

  void clearVehicle(VehicleId id) {
    _vehicleRecords[id]!.clear();
  }

  static VehicleId _vehicleFromTargetStatic(_ReportTarget target) {
    switch (target) {
      case _ReportTarget.vehicle1:
        return VehicleId.vehicle1;
      case _ReportTarget.vehicle2:
        return VehicleId.vehicle2;
      case _ReportTarget.vehicle3:
        return VehicleId.vehicle3;
      case _ReportTarget.vehicle4:
        return VehicleId.vehicle4;
      case _ReportTarget.vehicle5:
        return VehicleId.vehicle5;
      case _ReportTarget.all:
        return VehicleId.vehicle1;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFFF0F4F8);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFF1A2236);
  static const accent = Color(0xFF53D6FF);
  static const accentNav = Color(0xFF1A3A5C);
  static const red = Color(0xFFE53935);
  static const green = Color(0xFF43A047);
  static const orange = Color(0xFFFF8F00);
  static const textDark = Color(0xFF1A2236);
  static const textMid = Color(0xFF5A6A85);
  static const textLight = Color(0xFF9DAFC8);
  static const stroke = Color(0xFFE2E8F0);
  static const cardBg = Color(0xFFF7FAFF);
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORTS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _store = RouteStore.instance;
  _ReportTarget _target = _ReportTarget.all;
  VehicleId _vehicleFromTarget(_ReportTarget target) {
    switch (target) {
      case _ReportTarget.vehicle1:
        return VehicleId.vehicle1;
      case _ReportTarget.vehicle2:
        return VehicleId.vehicle2;
      case _ReportTarget.vehicle3:
        return VehicleId.vehicle3;
      case _ReportTarget.vehicle4:
        return VehicleId.vehicle4;
      case _ReportTarget.vehicle5:
        return VehicleId.vehicle5;
      case _ReportTarget.all:
        return VehicleId.vehicle1;
    }
  }

  String _targetLabel(_ReportTarget target) {
    switch (target) {
      case _ReportTarget.all:
        return 'Tümü';
      case _ReportTarget.vehicle1:
        return VehicleId.vehicle1.label;
      case _ReportTarget.vehicle2:
        return VehicleId.vehicle2.label;
      case _ReportTarget.vehicle3:
        return VehicleId.vehicle3.label;
      case _ReportTarget.vehicle4:
        return VehicleId.vehicle4.label;
      case _ReportTarget.vehicle5:
        return VehicleId.vehicle5.label;
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _fmtDur(int min) {
    if (min < 60) return '$min dk';
    return '${min ~/ 60}s ${min % 60}dk';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetState>();
    final dataset = _store.datasetForTarget(_target);

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CompactReportTargetBar(
                        target: _target,
                        onChanged: (next) {
                          if (next != _ReportTarget.all) {
                            fleet.selectVehicle(_vehicleFromTarget(next));
                          }
                          setState(() => _target = next);
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _targetLabel(_target),
                            style: const TextStyle(
                              color: _C.textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Rapor kapsamı',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _target == _ReportTarget.all
                      ? 'Şu an tüm araçların ortak rapor görünümü gösteriliyor.'
                      : '${_targetLabel(_target)} için araç bazlı rapor görünümü gösteriliyor.',
                  style: const TextStyle(
                    color: Color(0xFF5A6A85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // ── Başlık çubuğu ──────────────────────────────────────────────
          Container(
            color: _C.sidebar,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Geri butonu
                    InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _C.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: _C.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Raporlar',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${dataset.totalRoutes} rota kaydı — ${_targetLabel(_target)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (dataset.records.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Tüm verileri sil?'),
                              content: const Text(
                                'Oturum verileri temizlenecek.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('İptal'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _C.red,
                                  ),
                                  onPressed: () {
                                    if (_target == _ReportTarget.all) {
                                      _store.clear();
                                    } else {
                                      _store.clearVehicle(
                                        _vehicleFromTarget(_target),
                                      );
                                    }
                                    setState(() {});
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Sil'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                        label: const Text('Temizle'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Tab bar ───────────────────────────────────────────────
                TabBar(
                  controller: _tab,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: _C.accent,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.4),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'İstatistikler'),
                    Tab(text: 'Sık Adresler'),
                    Tab(text: 'Doluluk'),
                    Tab(text: 'Geçmiş'),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab içerikleri ─────────────────────────────────────────────
          Expanded(
            child: dataset.records.isEmpty
                ? _EmptyState(onTab: _tab)
                : TabBarView(
                    controller: _tab,
                    children: [
                      _StatsTab(dataset: dataset, fmtDur: _fmtDur),
                      _FrequencyTab(dataset: dataset),
                      _FillTab(dataset: dataset),
                      _HistoryTab(
                        dataset: dataset,
                        fmtDur: _fmtDur,
                        fmtDate: _fmtDate,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOŞ DURUM
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTab});
  final TabController onTab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _C.cardBg,
              shape: BoxShape.circle,
              border: Border.all(color: _C.stroke, width: 1.5),
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              size: 34,
              color: _C.textLight,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Henüz rota oluşturulmadı',
            style: TextStyle(
              color: _C.textDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Rota Paneli\'nden bir rota oluşturun,\nsonuçlar burada otomatik görünür.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.textLight, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — İSTATİSTİKLER
// ─────────────────────────────────────────────────────────────────────────────
class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.dataset, required this.fmtDur});
  final ReportDataset dataset;
  final String Function(int) fmtDur;

  @override
  Widget build(BuildContext context) {
    final byWeek = dataset.byWeek;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _BigStat(
                  icon: Icons.alt_route_rounded,
                  label: 'Toplam Rota',
                  value: '${dataset.totalRoutes}',
                  color: _C.accentNav,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.local_hospital_rounded,
                  label: 'Toplam Transfer',
                  value: '${dataset.totalTransfers}',
                  color: _C.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.route_rounded,
                  label: 'Toplam Mesafe',
                  value: '${dataset.totalKm.toStringAsFixed(1)} km',
                  color: _C.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.timer_rounded,
                  label: 'Toplam Süre',
                  value: fmtDur(dataset.totalMin),
                  color: _C.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BigStat(
                  icon: Icons.moving_rounded,
                  label: 'Ort. Mesafe/Rota',
                  value: '${dataset.avgKm.toStringAsFixed(1)} km',
                  color: const Color(0xFF8E24AA),
                  small: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.schedule_rounded,
                  label: 'Ort. Süre/Rota',
                  value: fmtDur(dataset.avgMin),
                  color: const Color(0xFF00897B),
                  small: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.pin_drop_rounded,
                  label: 'Ort. Durak/Rota',
                  value: dataset.totalRoutes == 0
                      ? '—'
                      : (dataset.totalTransfers / dataset.totalRoutes)
                            .toStringAsFixed(1),
                  color: _C.red,
                  small: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStat(
                  icon: Icons.calendar_today_rounded,
                  label: 'Hafta Sayısı',
                  value: '${byWeek.length}',
                  color: _C.textMid,
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (byWeek.isNotEmpty) ...[
            const _SectionHeader(
              title: 'Haftalık Özet',
              icon: Icons.calendar_view_week_rounded,
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.stroke),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: _C.cardBg,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Hafta Başı',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Rota',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Transfer',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Mesafe',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Süre',
                            style: TextStyle(
                              color: _C.textLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...byWeek.entries.toList().asMap().entries.map((e) {
                    final idx = e.key;
                    final week = e.value.key;
                    final recs = e.value.value;
                    final km = recs.fold(0.0, (s, r) => s + r.totalKm);
                    final min = recs.fold(0, (s, r) => s + r.totalMin);
                    final stops = recs.fold(0, (s, r) => s + r.stopCount);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: idx.isEven
                            ? Colors.transparent
                            : _C.cardBg.withOpacity(0.5),
                        border: Border(top: BorderSide(color: _C.stroke)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              week,
                              style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${recs.length}',
                              style: const TextStyle(
                                color: _C.accentNav,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '$stops',
                              style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${km.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              fmtDur(min),
                              style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — SIK ADRESLER
// ─────────────────────────────────────────────────────────────────────────────
class _FrequencyTab extends StatelessWidget {
  const _FrequencyTab({required this.dataset});
  final ReportDataset dataset;

  @override
  Widget build(BuildContext context) {
    final freq = dataset.addressFrequency;
    final entries = freq.entries.toList();
    final maxVal = entries.isEmpty ? 1 : entries.first.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'En Sık Ziyaret Edilen Adresler',
            icon: Icons.pin_drop_rounded,
          ),
          const SizedBox(height: 6),
          Text(
            '${entries.length} farklı adres • seçili kapsam',
            style: const TextStyle(color: _C.textLight, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          ...entries.asMap().entries.map((e) {
            final rank = e.key + 1;
            final addr = e.value.key;
            final count = e.value.value;
            final ratio = count / maxVal;

            Color rankColor = _C.textLight;
            if (rank == 1) rankColor = const Color(0xFFFFB300);
            if (rank == 2) rankColor = const Color(0xFF9E9E9E);
            if (rank == 3) rankColor = const Color(0xFF8D6E63);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: rank <= 3 ? rankColor.withOpacity(0.25) : _C.stroke,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rankColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              color: rankColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          addr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _C.textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _C.accentNav.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count kez',
                          style: const TextStyle(
                            color: _C.accentNav,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: _C.cardBg,
                      valueColor: AlwaysStoppedAnimation(
                        rank == 1 ? const Color(0xFFFFB300) : _C.accent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — DOLULUK ORANLARI
// ─────────────────────────────────────────────────────────────────────────────
class _FillTab extends StatelessWidget {
  const _FillTab({required this.dataset});
  final ReportDataset dataset;

  @override
  Widget build(BuildContext context) {
    final byDay = <String, _DayStats>{};
    for (final r in dataset.records) {
      final key = '${r.createdAt.day}/${r.createdAt.month}/${r.createdAt.year}';
      final s = byDay.putIfAbsent(key, () => _DayStats(label: key));
      final h = r.createdAt.hour;
      if (h < 12) {
        s.morningCount++;
      } else {
        s.afternoonCount++;
      }
      s.totalKm += r.totalKm;
      s.totalMin += r.totalMin;
    }

    final days = byDay.values.toList();
    final maxCount = days.isEmpty
        ? 1
        : days
              .map((d) => d.morningCount + d.afternoonCount)
              .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Sabah / Öğleden Sonra Dağılımı',
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(height: 16),
          _MorningAfternoonSummary(records: dataset.records),
          const SizedBox(height: 28),
          const _SectionHeader(
            title: 'Günlük Rota Yoğunluğu',
            icon: Icons.calendar_today_rounded,
          ),
          const SizedBox(height: 16),
          if (days.isEmpty)
            const Text('Henüz veri yok', style: TextStyle(color: _C.textLight))
          else
            ...days.map((day) {
              final total = day.morningCount + day.afternoonCount;
              final mRatio = total == 0 ? 0.0 : day.morningCount / maxCount;
              final aRatio = total == 0 ? 0.0 : day.afternoonCount / maxCount;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _C.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          day.label,
                          style: const TextStyle(
                            color: _C.textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$total rota',
                          style: const TextStyle(
                            color: _C.textLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _LabeledBar(
                      label: 'Sabah',
                      count: day.morningCount,
                      ratio: mRatio,
                      color: const Color(0xFF9DAFC8),
                    ),
                    const SizedBox(height: 6),
                    _LabeledBar(
                      label: 'Öğleden S.',
                      count: day.afternoonCount,
                      ratio: aRatio,
                      color: _C.accentNav,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DayStats {
  final String label;
  int morningCount = 0;
  int afternoonCount = 0;
  double totalKm = 0;
  int totalMin = 0;
  _DayStats({required this.label});
}

class _MorningAfternoonSummary extends StatelessWidget {
  const _MorningAfternoonSummary({required this.records});
  final List<RouteRecord> records;

  @override
  Widget build(BuildContext context) {
    int morning = 0, afternoon = 0;
    for (final r in records) {
      if (r.createdAt.hour < 12)
        morning++;
      else
        afternoon++;
    }
    final total = morning + afternoon;
    final mRatio = total == 0 ? 0.5 : morning / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.stroke),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ShiftCard(
                  label: 'Sabah',
                  subtitle: '(08:00 — 12:00)',
                  count: morning,
                  total: total,
                  color: const Color(0xFF9DAFC8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ShiftCard(
                  label: 'Öğleden Sonra',
                  subtitle: '(12:00 — 18:00)',
                  count: afternoon,
                  total: total,
                  color: _C.accentNav,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Dolu/boş gösterge bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (mRatio * 100).round(),
                    child: Container(color: const Color(0xFF9DAFC8)),
                  ),
                  Expanded(
                    flex: 100 - (mRatio * 100).round(),
                    child: Container(color: _C.accentNav),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Legend(color: const Color(0xFF9DAFC8), label: 'Sabah'),
              const SizedBox(width: 16),
              _Legend(color: _C.accentNav, label: 'Öğleden Sonra'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.label,
    required this.subtitle,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label, subtitle;
  final int count, total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (count / total * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(color: _C.textLight, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            '$count rota',
            style: const TextStyle(
              color: _C.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          Text(
            '%$pct',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledBar extends StatelessWidget {
  const _LabeledBar({
    required this.label,
    required this.count,
    required this.ratio,
    required this.color,
  });
  final String label;
  final int count;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: _C.textMid,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: _C.cardBg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: _C.textMid,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4 — GEÇMİŞ
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.dataset,
    required this.fmtDur,
    required this.fmtDate,
  });
  final ReportDataset dataset;
  final String Function(int) fmtDur;
  final String Function(DateTime) fmtDate;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: dataset.records.length,
      itemBuilder: (_, i) {
        final r = dataset.records[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.stroke),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _C.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${dataset.records.length - i}',
                          style: const TextStyle(
                            color: _C.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rota #${dataset.records.length - i}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            fmtDate(r.createdAt),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MiniStat(
                      label: 'Süre',
                      value: fmtDur(r.totalMin),
                      color: _C.accent,
                    ),
                    const SizedBox(width: 14),
                    _MiniStat(
                      label: 'Mesafe',
                      value: '${r.totalKm.toStringAsFixed(1)} km',
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(width: 14),
                    _MiniStat(
                      label: 'Durak',
                      value: '${r.stopCount}',
                      color: const Color(0xFFFFB74D),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: r.path.asMap().entries.map((e) {
                    final idx = e.key;
                    final addr = e.value;
                    final isFirst = idx == 0;
                    final isLast = idx == r.path.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isFirst
                            ? _C.green.withOpacity(0.08)
                            : isLast
                            ? _C.accentNav.withOpacity(0.08)
                            : _C.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isFirst
                              ? _C.green.withOpacity(0.3)
                              : isLast
                              ? _C.accentNav.withOpacity(0.25)
                              : _C.stroke,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: isFirst
                                  ? _C.green
                                  : isLast
                                  ? _C.accentNav
                                  : _C.textLight,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              addr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _C.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORTAK KÜÇÜK WİDGET'LAR
// ─────────────────────────────────────────────────────────────────────────────
class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.small = false,
  });
  final IconData icon;
  final String label, value;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: small ? 18 : 22,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _C.textLight,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _C.accentNav),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: _C.textDark,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _ReportScopeChip extends StatelessWidget {
  const _ReportScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1A3A5C) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1A3A5C)
                  : const Color(0xFFD8E1EC),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF1A2236),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactReportTargetBar extends StatelessWidget {
  const _CompactReportTargetBar({
    required this.target,
    required this.onChanged,
  });

  final _ReportTarget target;
  final ValueChanged<_ReportTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ReportScopeChip(
              label: 'Tümü',
              selected: target == _ReportTarget.all,
              onTap: () => onChanged(_ReportTarget.all),
            ),
            const SizedBox(width: 8),
            _ReportScopeChip(
              label: VehicleId.vehicle1.label,
              selected: target == _ReportTarget.vehicle1,
              onTap: () => onChanged(_ReportTarget.vehicle1),
            ),
            const SizedBox(width: 8),
            _ReportScopeChip(
              label: VehicleId.vehicle2.label,
              selected: target == _ReportTarget.vehicle2,
              onTap: () => onChanged(_ReportTarget.vehicle2),
            ),
            const SizedBox(width: 8),
            _ReportScopeChip(
              label: VehicleId.vehicle3.label,
              selected: target == _ReportTarget.vehicle3,
              onTap: () => onChanged(_ReportTarget.vehicle3),
            ),
            const SizedBox(width: 8),
            _ReportScopeChip(
              label: VehicleId.vehicle4.label,
              selected: target == _ReportTarget.vehicle4,
              onTap: () => onChanged(_ReportTarget.vehicle4),
            ),
            const SizedBox(width: 8),
            _ReportScopeChip(
              label: VehicleId.vehicle5.label,
              selected: target == _ReportTarget.vehicle5,
              onTap: () => onChanged(_ReportTarget.vehicle5),
            ),
          ],
        ),
      ),
    );
  }
}