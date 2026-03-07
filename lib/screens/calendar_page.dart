import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../data/address_store.dart';
import '../core/models/address.dart';
import '../services/osrm_route_service.dart';
import '../services/tsp_optimizer_service.dart';

// Vardiya tipi — VisitPlanItem.shift alanı ile eşleşir
// (Aynı tanım calendar_event.dart/auth_service.dart'a da eklenecek)

// ─────────────────────────────────────────────────────────────────────────────
// TOKENS — ana sayfayla uyumlu renk paleti
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
  static const strokeMid = Color(0xFFCDD5E0);
  static const today = Color(0xFF1A3A5C);
  static const cardBg = Color(0xFFF7FAFF);
}

// Türkçe gün kısaltmaları
const _dayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
// Tüm günler için tek renk — lacivert/accent sistemi
const _dayColors = [
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
  Color(0xFF53D6FF),
];

enum ShiftType { morning, afternoon }

extension ShiftLabel on ShiftType {
  String get label => this == ShiftType.morning ? 'Sabah' : 'Öğleden Sonra';
  String get short => this == ShiftType.morning ? 'SAB' : 'ÖS';
  IconData get icon => this == ShiftType.morning
      ? Icons.schedule_rounded
      : Icons.access_time_filled_rounded;
  // Her iki vardiya da aynı nötr renk sistemi
  Color get color => const Color(0xFF5A6A85);
  Color get bg => const Color(0xFFF7FAFF);
}

class _MovePayload {
  final DateTime fromDay;
  final int fromIndex;
  final VisitPlanItem item;
  final ShiftType shift;
  const _MovePayload({
    required this.fromDay,
    required this.fromIndex,
    required this.item,
    required this.shift,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CALENDAR PAGE
// ─────────────────────────────────────────────────────────────────────────────
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.onSendToRoute, this.fixedHomeAddress});

  /// Seçili gündeki adresleri rota paneline gönderir
  final void Function(List<String> addresses)? onSendToRoute;
  final Address? fixedHomeAddress;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with TickerProviderStateMixin {
  static const int maxDaily = 10;
  static const int repeatHorizonDays = 730;

  List<Address> get addresses => AddressStore.items;
  Address? selectedAddress;

  late DateTime weekStart;
  late DateTime selectedDay;
  // Gün → Vardiya → Görev listesi
  final Map<DateTime, Map<ShiftType, List<VisitPlanItem>>> _planByDay = {};
  final OsrmRouteService _osrm = const OsrmRouteService();
  final TspOptimizerService _tsp = const TspOptimizerService();
  final Map<DateTime, Map<ShiftType, String?>> _forcedFirstStopByDay = {};
  // animasyon — hafta geçişi
  late AnimationController _weekCtrl;
  late Animation<double> _weekFade;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    weekStart = _startOfWeek(now);
    selectedDay = _dateOnly(now);

    _weekCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _weekFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _weekCtrl, curve: Curves.easeOut));
    _weekCtrl.forward();
  }

  @override
  void dispose() {
    _weekCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isToday(DateTime d) => _sameDay(d, DateTime.now());

  DateTime _startOfWeek(DateTime d) {
    final only = _dateOnly(d);
    return only.subtract(Duration(days: only.weekday - DateTime.monday));
  }

  String _newSeriesId(String title) =>
      '${DateTime.now().microsecondsSinceEpoch}-${title.hashCode}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _C.accentNav,
        ),
      );
  }

  int _countForDay(DateTime dayKey) {
    final m = _planByDay[dayKey];
    if (m == null) return 0;
    return (m[ShiftType.morning]?.length ?? 0) +
        (m[ShiftType.afternoon]?.length ?? 0);
  }

  int _countShift(DateTime dayKey, ShiftType shift) =>
      (_planByDay[dayKey]?[shift] ?? const []).length;

  List<VisitPlanItem> _listForShift(DateTime dayKey, ShiftType shift) {
    final dayMap = _planByDay.putIfAbsent(dayKey, () => {});
    return dayMap.putIfAbsent(shift, () => <VisitPlanItem>[]);
  }

  void _changeWeek(int direction) {
    _weekCtrl.reset();
    setState(() => weekStart = weekStart.add(Duration(days: 7 * direction)));
    _weekCtrl.forward();
  }

  // ── Series ops (orijinalden değişmedi) ───────────────────────────────────
  void _removeSeriesEverywhere(String seriesId) {
    for (final dayMap in _planByDay.values) {
      for (final list in dayMap.values) {
        list.removeWhere((it) => it.seriesId == seriesId);
      }
    }
  }

  bool _addItemToShift(DateTime dayKey, ShiftType shift, VisitPlanItem item) {
    final list = _listForShift(dayKey, shift);
    if (list.length >= maxDaily) return false;
    list.add(item);
    return true;
  }

  void _addWithRepeat({
    required DateTime baseDay,
    required VisitPlanItem item,
    required ShiftType shift,
  }) {
    final baseKey = _dateOnly(baseDay);
    if (_countShift(baseKey, shift) >= maxDaily) {
      _toast('Bu vardiya için limit dolu (max $maxDaily).');
      return;
    }
    _addItemToShift(baseKey, shift, item);
    if (item.repeat == RepeatType.none) return;

    int i = 1;
    while (i <= repeatHorizonDays) {
      DateTime occ;
      switch (item.repeat) {
        case RepeatType.daily:
          occ = baseKey.add(Duration(days: i));
          break;
        case RepeatType.weekly:
          occ = baseKey.add(Duration(days: i * 7));
          break;
        case RepeatType.monthly:
          occ = DateTime(baseKey.year, baseKey.month + i, baseKey.day);
          occ = _dateOnly(occ);
          break;
        case RepeatType.none:
          occ = baseKey;
          break;
      }
      if (_countShift(occ, shift) < maxDaily) _addItemToShift(occ, shift, item);
      i++;
    }
  }

  void _reorderWithinShift(
    DateTime dayKey,
    ShiftType shift,
    int oldIndex,
    int newIndex,
  ) {
    final list = _planByDay[dayKey]?[shift];
    if (list == null || oldIndex < 0 || oldIndex >= list.length) return;

    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= list.length) newIndex = list.length - 1;

    final movedTitle = list[oldIndex].title;

    setState(() {
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
    });

    if (newIndex == 0) {
      _setForcedFirstTitle(dayKey, shift, movedTitle);
      _toast('"$movedTitle" öncelikli ilk durak olarak ayarlandı.');
    }

    // Her reorder sonrası algoritma tekrar düzenlesin.
    _optimizeShiftForDay(dayKey, shift);
  }

  void _moveItemToDay(
    _MovePayload payload,
    DateTime targetDay,
    ShiftType targetShift,
  ) {
    final fromKey = _dateOnly(payload.fromDay);
    final toKey = _dateOnly(targetDay);
    final fromShift = payload.shift;

    if (_sameDay(fromKey, toKey) && fromShift == targetShift) return;
    if (_countShift(toKey, targetShift) >= maxDaily) {
      _toast('Hedef vardiya dolu (max $maxDaily).');
      return;
    }

    final fromList = _planByDay[fromKey]?[fromShift];
    if (fromList == null || payload.fromIndex >= fromList.length) return;

    setState(() {
      fromList.removeAt(payload.fromIndex);
      _listForShift(toKey, targetShift).add(payload.item);
    });
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  Future<VisitPlanItem?> _showAddOrEditDialog({
    required String title,
    VisitPlanItem? existing,
  }) async {
    RepeatType selected = existing?.repeat ?? RepeatType.none;
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final res = await showDialog<VisitPlanItem>(
      context: context,
      builder: (_) => _PlanDialog(
        title: title,
        existing: existing,
        initialRepeat: selected,
        noteCtrl: noteCtrl,
        newSeriesId: _newSeriesId,
      ),
    );
    noteCtrl.dispose();
    return res;
  }

  Future<void> _handleDropAddress(
    Address address,
    DateTime dayKey,
    ShiftType shift,
  ) async {
    if (_countShift(dayKey, shift) >= maxDaily) {
      _toast('Bu vardiya için limit dolu (max $maxDaily).');
      return;
    }

    final item = await _showAddOrEditDialog(title: address.address);
    if (item == null) return;

    setState(() {
      _addWithRepeat(baseDay: dayKey, item: item, shift: shift);
    });

    // Yeni adres eklendikten sonra o vardiyayı otomatik optimize et.
    await _optimizeShiftForDay(dayKey, shift);
  }

  Future<void> _editItem(DateTime dayKey, ShiftType shift, int index) async {
    final list = _planByDay[dayKey]?[shift];
    if (list == null || index < 0 || index >= list.length) return;
    final old = list[index];
    final updated = await _showAddOrEditDialog(title: old.title, existing: old);
    if (updated == null) return;
    setState(() {
      _removeSeriesEverywhere(old.seriesId);
      _addWithRepeat(baseDay: dayKey, item: updated, shift: shift);
    });
  }

  Address? _addressByTitle(String title) {
    for (final a in AddressStore.items) {
      if (a.address == title) return a;
    }
    return null;
  }

  List<VisitPlanItem> _rebuildItemsInOrder(
    List<VisitPlanItem> original,
    List<String> orderedTitles,
  ) {
    final pool = List<VisitPlanItem>.from(original);
    final result = <VisitPlanItem>[];

    for (final title in orderedTitles) {
      final idx = pool.indexWhere((e) => e.title == title);
      if (idx == -1) continue;
      result.add(pool.removeAt(idx));
    }

    // Güvenlik: eşleşmeyenler sonda kalsın
    result.addAll(pool);
    return result;
  }

  String? _forcedFirstTitle(DateTime dayKey, ShiftType shift) {
    return _forcedFirstStopByDay[dayKey]?[shift];
  }

  void _setForcedFirstTitle(DateTime dayKey, ShiftType shift, String? title) {
    if (title == null) {
      final dayMap = _forcedFirstStopByDay[dayKey];
      dayMap?.remove(shift);
      if (dayMap != null && dayMap.isEmpty) {
        _forcedFirstStopByDay.remove(dayKey);
      }
      return;
    }

    final dayMap = _forcedFirstStopByDay.putIfAbsent(dayKey, () => {});
    dayMap[shift] = title;
  }

  List<int> _solveExactPath({
    required List<List<double>> cost,
    required int start,
    required int end,
  }) {
    final n = cost.length;
    if (n == 0) return const [];
    if (start == end) return [start];

    final internal = <int>[];
    for (int i = 0; i < n; i++) {
      if (i != start && i != end) internal.add(i);
    }

    if (internal.isEmpty) return [start, end];

    final m = internal.length;
    final subsetCount = 1 << m;

    final dp = List.generate(
      subsetCount,
      (_) => List<double>.filled(m, double.infinity),
    );
    final parent = List.generate(subsetCount, (_) => List<int>.filled(m, -1));

    // Base: start -> internal[j]
    for (int j = 0; j < m; j++) {
      final mask = 1 << j;
      dp[mask][j] = cost[start][internal[j]];
      parent[mask][j] = -1;
    }

    for (int mask = 1; mask < subsetCount; mask++) {
      for (int j = 0; j < m; j++) {
        if ((mask & (1 << j)) == 0) continue;
        final prevMask = mask ^ (1 << j);
        if (prevMask == 0) continue;

        for (int k = 0; k < m; k++) {
          if ((prevMask & (1 << k)) == 0) continue;
          final cand = dp[prevMask][k] + cost[internal[k]][internal[j]];
          if (cand < dp[mask][j]) {
            dp[mask][j] = cand;
            parent[mask][j] = k;
          }
        }
      }
    }

    final fullMask = subsetCount - 1;
    double best = double.infinity;
    int bestLast = -1;

    for (int j = 0; j < m; j++) {
      final cand = dp[fullMask][j] + cost[internal[j]][end];
      if (cand < best) {
        best = cand;
        bestLast = j;
      }
    }

    if (bestLast == -1) {
      throw StateError('Sabit ilk durak için geçerli rota üretilemedi.');
    }

    final reversedInternal = <int>[];
    int mask = fullMask;
    int current = bestLast;
    while (current != -1) {
      reversedInternal.add(internal[current]);
      final prev = parent[mask][current];
      mask ^= (1 << current);
      current = prev;
    }

    final orderedInternal = reversedInternal.reversed.toList();
    return [start, ...orderedInternal, end];
  }

  Future<void> _optimizeShiftForDay(DateTime dayKey, ShiftType shift) async {
    final home = widget.fixedHomeAddress;
    if (home == null || home.lat == null || home.lng == null) {
      _toast('Önce sabit ev/başlangıç konumu belirlenmeli.');
      return;
    }

    final list = _listForShift(dayKey, shift);
    if (list.length <= 1) return;

    final stops = <Address>[];
    for (final item in list) {
      final a = _addressByTitle(item.title);
      if (a == null || a.lat == null || a.lng == null) {
        _toast('"${item.title}" için koordinat bulunamadı.');
        return;
      }
      if (a.address == home.address) continue;
      stops.add(a);
    }

    if (stops.length <= 1) return;

    // Öncelikli ilk durak (home'dan sonra gidilecek ilk adres)
    Address? forcedFirst;
    final forcedTitle = _forcedFirstTitle(dayKey, shift);
    if (forcedTitle != null) {
      for (final s in stops) {
        if (s.address == forcedTitle) {
          forcedFirst = s;
          break;
        }
      }
      // Artık listede yoksa constraint'i temizle
      if (forcedFirst == null) {
        _setForcedFirstTitle(dayKey, shift, null);
      }
    }

    try {
      List<String> orderedTitles;

      if (forcedFirst == null) {
        // Normal exact closed tour: HOME -> stops -> HOME
        final nodes = <Address>[home, ...stops];

        final matrix = await _osrm.table(
          coords: nodes
              .map((a) => LatLng(a.lat!, a.lng!))
              .toList(growable: false),
        );

        final cost = List<List<double>>.generate(
          matrix.n,
          (i) => List<double>.generate(matrix.n, (j) {
            final v = matrix.durationsSeconds[i][j];
            if (v == null) return 1e15;
            return v;
          }),
        );

        final tsp = _tsp.solveExact(cost);

        // [home, stopA, stopB, ..., home] -> sadece durakları al
        orderedTitles = tsp.route
            .skip(1)
            .take(tsp.route.length - 2)
            .map((idx) => nodes[idx].address)
            .toList();
      } else {
        // Zorunlu ilk durak varsa:
        // HOME -> forcedFirst sabit,
        // sonra remaining -> HOME exact path optimize edilir.
        final remaining = <Address>[];
        for (final s in stops) {
          if (s.address != forcedFirst.address) remaining.add(s);
        }

        if (remaining.isEmpty) {
          orderedTitles = [forcedFirst.address];
        } else {
          // [forcedFirst, remaining..., home]
          final nodes = <Address>[forcedFirst, ...remaining, home];

          final matrix = await _osrm.table(
            coords: nodes
                .map((a) => LatLng(a.lat!, a.lng!))
                .toList(growable: false),
          );

          final cost = List<List<double>>.generate(
            matrix.n,
            (i) => List<double>.generate(matrix.n, (j) {
              final v = matrix.durationsSeconds[i][j];
              if (v == null) return 1e15;
              return v;
            }),
          );

          // Exact path: forcedFirst -> remaining -> home
          final pathIdx = _solveExactPath(
            cost: cost,
            start: 0,
            end: nodes.length - 1,
          );

          // [forcedFirst, stopX, stopY, home] -> home hariç hepsini al
          orderedTitles = pathIdx
              .take(pathIdx.length - 1)
              .map((idx) => nodes[idx].address)
              .toList();
        }
      }

      final reordered = _rebuildItemsInOrder(list, orderedTitles);

      if (!mounted) return;
      setState(() {
        list
          ..clear()
          ..addAll(reordered);
      });
    } catch (e) {
      _toast('Optimizasyon hatası: $e');
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final days = List<DateTime>.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );
    if (selectedAddress != null &&
        !addresses.any((a) => a.code == selectedAddress!.code)) {
      selectedAddress = null;
    }

    // Hafta aralığı metni
    final wEnd = weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${weekStart.day} ${_monthShort(weekStart.month)} — ${wEnd.day} ${_monthShort(wEnd.month)} ${wEnd.year}';

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          // ── Top Bar ─────────────────────────────────────────────────────
          _TopBar(
            weekLabel: weekLabel,
            addresses: addresses,
            selectedAddress: selectedAddress,
            selectedDay: selectedDay,
            onBack: () => Navigator.of(context).maybePop(),
            onPrevWeek: () => _changeWeek(-1),
            onNextWeek: () => _changeWeek(1),
            onAddressChanged: (v) => setState(() => selectedAddress = v),
            onSendToRoute: widget.onSendToRoute == null
                ? null
                : () {
                    final addrs = _addressesForDay(selectedDay);
                    if (addrs.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Seçili günde planlanmış adres yok.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    widget.onSendToRoute!(addrs);
                    Navigator.of(context).maybePop();
                  },
          ),

          // ── Haftalık kolonlar ────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _weekFade,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: days.asMap().entries.map((entry) {
                    final i = entry.key;
                    final day = entry.value;
                    final dayKey = _dateOnly(day);
                    final isSel = _sameDay(dayKey, selectedDay);
                    final isToday = _isToday(day);

                    final morningList =
                        _planByDay[dayKey]?[ShiftType.morning] ??
                        <VisitPlanItem>[];
                    final afternoonList =
                        _planByDay[dayKey]?[ShiftType.afternoon] ??
                        <VisitPlanItem>[];
                    return _DayColumn(
                      day: day,
                      dayKey: dayKey,
                      dayIndex: i,
                      morningList: morningList,
                      afternoonList: afternoonList,
                      isSelected: isSel,
                      isToday: isToday,
                      maxDaily: maxDaily,
                      onTapHeader: () => setState(() => selectedDay = dayKey),
                      onAcceptDrop: (data, shift) {
                        if (data is Address)
                          _handleDropAddress(data, dayKey, shift);
                        if (data is _MovePayload)
                          setState(() => _moveItemToDay(data, dayKey, shift));
                      },
                      onEditItem: (shift, idx) => _editItem(dayKey, shift, idx),
                      onReorder: (shift, o, n) =>
                          _reorderWithinShift(dayKey, shift, o, n),
                      buildMovePayload: (shift, idx) {
                        final list = shift == ShiftType.morning
                            ? morningList
                            : afternoonList;
                        return _MovePayload(
                          fromDay: dayKey,
                          fromIndex: idx,
                          item: list[idx],
                          shift: shift,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Seçili günün tüm vardiya adreslerini döndürür
  List<String> _addressesForDay(DateTime day) {
    final key = _dateOnly(day);
    final dayMap = _planByDay[key];
    if (dayMap == null) return [];
    final result = <String>[];
    for (final list in dayMap.values) {
      result.addAll(list.map((e) => e.title));
    }
    return result;
  }

  String _monthShort(int m) => [
    '',
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ][m];

  String _fullDate(DateTime d) {
    const months = [
      '',
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.weekLabel,
    required this.addresses,
    required this.selectedAddress,
    required this.selectedDay,
    required this.onBack,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onAddressChanged,
    this.onSendToRoute,
  });

  final String weekLabel;
  final List<Address> addresses;
  final Address? selectedAddress;
  final DateTime selectedDay;
  final VoidCallback onBack, onPrevWeek, onNextWeek;
  final ValueChanged<Address?> onAddressChanged;
  final VoidCallback? onSendToRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          // Geri
          _NavBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
          const SizedBox(width: 4),

          // Hafta navigasyonu
          _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrevWeek),
          _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNextWeek),
          const SizedBox(width: 12),

          // Hafta etiketi
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Haftalık Takvim',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                weekLabel,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Rotaya Gönder butonu
          if (onSendToRoute != null) ...[
            FilledButton.icon(
              onPressed: onSendToRoute,
              icon: const Icon(Icons.alt_route_rounded, size: 16),
              label: const Text('Rotaya Gönder'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF53D6FF),
                foregroundColor: const Color(0xFF0D2137),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Adres seçici (açılan listeden doğrudan sürüklenebilir)
          _AddressPickerControl(
            addresses: addresses,
            selectedAddress: selectedAddress,
            onChanged: onAddressChanged,
          ),

          // Sürüklenebilir adres kapsülü
          if (selectedAddress != null) ...[
            const SizedBox(width: 10),
            Draggable<Object>(
              data: selectedAddress!,
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _C.accentNav,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      selectedAddress!.address,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.5,
                child: _DragPill(label: selectedAddress!.address),
              ),
              child: _DragPill(label: selectedAddress!.address),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 18),
      ),
    );
  }
}

class _DragPill extends StatelessWidget {
  const _DragPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF53D6FF), Color(0xFF3DBFDB)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.drag_indicator_rounded,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressPickerControl extends StatefulWidget {
  const _AddressPickerControl({
    required this.addresses,
    required this.selectedAddress,
    required this.onChanged,
  });

  final List<Address> addresses;
  final Address? selectedAddress;
  final ValueChanged<Address?> onChanged;

  @override
  State<_AddressPickerControl> createState() => _AddressPickerControlState();
}

class _AddressPickerControlState extends State<_AddressPickerControl> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _open = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_open) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = _buildOverlay();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _open = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _open = false);
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 46),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 260,
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2236),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: widget.addresses.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Adres bulunamadı',
                          style: TextStyle(
                            color: Color(0xFF9DAFC8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shrinkWrap: true,
                        itemCount: widget.addresses.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.white.withOpacity(0.06),
                        ),
                        itemBuilder: (_, i) {
                          final a = widget.addresses[i];

                          final row = InkWell(
                            onTap: () {
                              widget.onChanged(a);
                              _removeOverlay();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 15,
                                    color: Color(0xFF9DAFC8),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      a.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                          return Draggable<Object>(
                            data: a,
                            feedback: Material(
                              color: Colors.transparent,
                              child: _FloatingAddressChip(text: a.address),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: row,
                            ),
                            child: row,
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: 260,
        height: 40,
        child: InkWell(
          onTap: _toggleOverlay,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 15,
                  color: Color(0xFF9DAFC8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.selectedAddress?.address ?? 'Adres Seç',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selectedAddress == null
                          ? const Color(0xFF9DAFC8)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: widget.selectedAddress == null
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.white.withOpacity(0.6),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingAddressChip extends StatelessWidget {
  const _FloatingAddressChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF53D6FF).withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_rounded,
            size: 16,
            color: Color(0xFF53D6FF),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2236),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GÜN KOLONU — Sabah / Öğleden Sonra bölümlü
// ─────────────────────────────────────────────────────────────────────────────
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.dayKey,
    required this.dayIndex,
    required this.morningList,
    required this.afternoonList,
    required this.isSelected,
    required this.isToday,
    required this.maxDaily,
    required this.onTapHeader,
    required this.onAcceptDrop,
    required this.onEditItem,
    required this.onReorder,
    required this.buildMovePayload,
  });

  final DateTime day, dayKey;
  final int dayIndex;
  final List<VisitPlanItem> morningList, afternoonList;
  final bool isSelected, isToday;
  final int maxDaily;
  final VoidCallback onTapHeader;
  final void Function(Object, ShiftType) onAcceptDrop;
  final void Function(ShiftType, int) onEditItem;
  final void Function(ShiftType, int, int) onReorder;
  final _MovePayload Function(ShiftType, int) buildMovePayload;

  Color get _accent => _dayColors[dayIndex];
  int get _total => morningList.length + afternoonList.length;

  static const _months = [
    '',
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  String _turkishDate(DateTime d) => '${d.day} ${_months[d.month]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? _accent.withOpacity(0.45) : _C.stroke,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? _accent.withOpacity(0.08)
                : Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Kolon başlığı ────────────────────────────────────────────
          GestureDetector(
            onTap: onTapHeader,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: isToday ? _C.accentNav : _accent.withOpacity(0.04),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dayNames[dayIndex],
                              style: TextStyle(
                                color: isToday ? Colors.white : _C.textDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              _turkishDate(day),
                              style: TextStyle(
                                color: isToday
                                    ? Colors.white.withOpacity(0.8)
                                    : _C.textMid,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FillBadge(
                        count: _total,
                        max: maxDaily * 2,
                        color: _accent,
                        dark: isToday,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _total / (maxDaily * 2),
                      minHeight: 4,
                      backgroundColor: isToday
                          ? Colors.white.withOpacity(0.15)
                          : _accent.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(
                        _total / (maxDaily * 2) > 0.8 ? _C.red : _accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── İki vardiya bölümü ────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: _ShiftSection(
                    shift: ShiftType.morning,
                    list: morningList,
                    dayKey: dayKey,
                    accent: _accent,
                    maxDaily: maxDaily,
                    onAcceptDrop: (data) =>
                        onAcceptDrop(data, ShiftType.morning),
                    onEditItem: (idx) => onEditItem(ShiftType.morning, idx),
                    onReorder: (o, n) => onReorder(ShiftType.morning, o, n),
                    buildMovePayload: (idx) =>
                        buildMovePayload(ShiftType.morning, idx),
                  ),
                ),
                // Ayırıcı çizgi
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  height: 1,
                  color: _C.stroke,
                ),
                Expanded(
                  flex: 1,
                  child: _ShiftSection(
                    shift: ShiftType.afternoon,
                    list: afternoonList,
                    dayKey: dayKey,
                    accent: _accent,
                    maxDaily: maxDaily,
                    onAcceptDrop: (data) =>
                        onAcceptDrop(data, ShiftType.afternoon),
                    onEditItem: (idx) => onEditItem(ShiftType.afternoon, idx),
                    onReorder: (o, n) => onReorder(ShiftType.afternoon, o, n),
                    buildMovePayload: (idx) =>
                        buildMovePayload(ShiftType.afternoon, idx),
                  ),
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
// VARDİYA BÖLÜMÜ — Sabah veya Öğleden Sonra
// ─────────────────────────────────────────────────────────────────────────────
class _ShiftSection extends StatelessWidget {
  const _ShiftSection({
    required this.shift,
    required this.list,
    required this.dayKey,
    required this.accent,
    required this.maxDaily,
    required this.onAcceptDrop,
    required this.onEditItem,
    required this.onReorder,
    required this.buildMovePayload,
  });

  final ShiftType shift;
  final List<VisitPlanItem> list;
  final DateTime dayKey;
  final Color accent;
  final int maxDaily;
  final ValueChanged<Object> onAcceptDrop;
  final ValueChanged<int> onEditItem;
  final Function(int, int) onReorder;
  final _MovePayload Function(int) buildMovePayload;

  @override
  Widget build(BuildContext context) {
    final isMorning = shift == ShiftType.morning;
    // Her iki vardiya — aynı nötr ton, sadece ince sol çizgi ayrımı
    const shiftColor = Color(0xFF5A6A85);
    const shiftBg = Color(0xFFF7FAFF);
    final borderAccent = isMorning
        ? const Color(0xFF9DAFC8)
        : const Color(0xFF53D6FF);

    return DragTarget<Object>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onAcceptDrop(d.data),
      builder: (context, candidate, _) {
        final isDragOver = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isDragOver
                ? _C.accent.withOpacity(0.04)
                : Colors.transparent,
            border: isDragOver
                ? Border.all(color: _C.accent.withOpacity(0.4), width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vardiya başlığı — sol ince çizgi ile ayrım
              Container(
                color: shiftBg,
                child: Row(
                  children: [
                    // Sol ince çizgi
                    Container(width: 3, height: 36, color: borderAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Text(
                              shift.label.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF5A6A85),
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: list.length >= maxDaily
                                    ? _C.red.withOpacity(0.08)
                                    : _C.stroke,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${list.length}/$maxDaily',
                                style: TextStyle(
                                  color: list.length >= maxDaily
                                      ? _C.red
                                      : _C.textLight,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Görev listesi
              if (list.isEmpty)
                _EmptyShiftState(isDragOver: isDragOver, color: shiftColor)
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: list.length,
                  buildDefaultDragHandles: false,
                  onReorder: onReorder,
                  itemBuilder: (_, idx) {
                    final item = list[idx];
                    return _TaskCard(
                      key: ValueKey(
                        '${dayKey.toIso8601String()}-${shift.name}-$idx-${item.seriesId}',
                      ),
                      item: item,
                      index: idx,
                      accent: accent,
                      onEdit: () => onEditItem(idx),
                      movePayload: buildMovePayload(idx),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyShiftState extends StatelessWidget {
  const _EmptyShiftState({required this.isDragOver, required this.color});
  final bool isDragOver;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Center(
        child: isDragOver
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 14, color: _C.accent),
                  const SizedBox(width: 4),
                  const Text(
                    'Bırak',
                    style: TextStyle(
                      color: _C.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : const Text(
                '—',
                style: TextStyle(
                  color: _C.strokeMid,
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOLULUK ROZETİ
// ─────────────────────────────────────────────────────────────────────────────
class _FillBadge extends StatelessWidget {
  const _FillBadge({
    required this.count,
    required this.max,
    required this.color,
    required this.dark,
  });
  final int count, max;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final full = count >= max;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: full
            ? _C.red.withOpacity(0.12)
            : dark
            ? Colors.white.withOpacity(0.12)
            : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: full
              ? _C.red.withOpacity(0.4)
              : dark
              ? Colors.white.withOpacity(0.2)
              : color.withOpacity(0.3),
        ),
      ),
      child: Text(
        '$count/$max',
        style: TextStyle(
          color: full
              ? _C.red
              : dark
              ? Colors.white
              : color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GÖREV KARTI
// ─────────────────────────────────────────────────────────────────────────────
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    super.key,
    required this.item,
    required this.index,
    required this.accent,
    required this.onEdit,
    required this.movePayload,
  });

  final VisitPlanItem item;
  final int index;
  final Color accent;
  final VoidCallback onEdit;
  final _MovePayload movePayload;

  Color _repeatColor() {
    switch (item.repeat) {
      case RepeatType.daily:
        return _C.accentNav;
      case RepeatType.weekly:
        return _C.accentNav;
      case RepeatType.monthly:
        return _C.accentNav;
      case RepeatType.none:
        return _C.textLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _C.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Renkli üst çizgi
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık + düzenle
                Row(
                  children: [
                    // Sıra numarası
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _C.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),

                if (item.note != null && item.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _C.textMid,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: 8),

                // Alt satır — tekrar rozeti + taşı + sırala
                Row(
                  children: [
                    // Tekrar rozeti
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _repeatColor().withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _repeatColor().withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        item.repeat.short,
                        style: TextStyle(
                          color: _repeatColor(),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Sıralama tutamacı
                    ReorderableDragStartListener(
                      index: index,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _C.stroke,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.drag_handle_rounded,
                          size: 14,
                          color: _C.textLight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Gün arası sürükle
                    Draggable<Object>(
                      data: movePayload,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _C.accentNav,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              item.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: accent,
                          ),
                        ),
                      ),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 14,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
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
// PLAN DİYALOĞU — modern tasarım
// ─────────────────────────────────────────────────────────────────────────────
class _PlanDialog extends StatefulWidget {
  const _PlanDialog({
    required this.title,
    required this.existing,
    required this.initialRepeat,
    required this.noteCtrl,
    required this.newSeriesId,
  });
  final String title;
  final VisitPlanItem? existing;
  final RepeatType initialRepeat;
  final TextEditingController noteCtrl;
  final String Function(String) newSeriesId;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late RepeatType _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialRepeat;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _C.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: _C.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.existing == null
                              ? 'Plan Ekle'
                              : 'Planı Düzenle',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tekrar seçimi
                  const Text(
                    'Tekrar',
                    style: TextStyle(
                      color: _C.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Chip'lerle tekrar seçimi
                  Wrap(
                    spacing: 8,
                    children: RepeatType.values.map((t) {
                      final sel = t == _selected;
                      return GestureDetector(
                        onTap: () => setState(() => _selected = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? _C.accentNav : _C.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? _C.accentNav : _C.stroke,
                              width: sel ? 0 : 1,
                            ),
                          ),
                          child: Text(
                            t.label,
                            style: TextStyle(
                              color: sel ? Colors.white : _C.textMid,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Not alanı
                  const Text(
                    'Not',
                    style: TextStyle(
                      color: _C.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.noteCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: _C.textDark, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Not yaz...',
                      hintStyle: const TextStyle(color: _C.textLight),
                      filled: true,
                      fillColor: _C.cardBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _C.stroke),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _C.stroke),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: _C.accent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Butonlar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.textMid,
                        side: const BorderSide(color: _C.stroke),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'İptal',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        final note = widget.noteCtrl.text.trim();
                        Navigator.pop(
                          context,
                          VisitPlanItem(
                            title: widget.title,
                            repeat: _selected,
                            note: note.isEmpty ? null : note,
                            seriesId:
                                widget.existing?.seriesId ??
                                widget.newSeriesId(widget.title),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.accentNav,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Kaydet',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
