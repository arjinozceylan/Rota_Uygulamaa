import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/address.dart';
import '../models/calendar_event.dart';
import '../services/fleet_state.dart';
import '../widgets/vehicle_selector_bar.dart';
import 'calendar_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOKENS — calendar_page.dart'taki paletle aynı
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFFF0F4F8);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFF1A2236);
  static const accent = Color(0xFF53D6FF);
  static const textDark = Color(0xFF1A2236);
  static const textMid = Color(0xFF5A6A85);
  static const textLight = Color(0xFF9DAFC8);
  static const stroke = Color(0xFFE2E8F0);
}

const _weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const _monthNames = [
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

class _DensityBand {
  const _DensityBand(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

/// Rota yoğunluğuna göre gün hücresi rengi.
_DensityBand _densityFor(int count) {
  if (count <= 0) return const _DensityBand(_C.surface, _C.textLight);
  if (count <= 5) {
    return const _DensityBand(Color(0xFFE6F1FB), Color(0xFF185FA5));
  }
  if (count <= 10) {
    return const _DensityBand(Color(0xFFEAF3DE), Color(0xFF3B6D11));
  }
  if (count <= 15) {
    return const _DensityBand(Color(0xFFFAEEDA), Color(0xFF854F0B));
  }
  return const _DensityBand(Color(0xFFFCEBEB), Color(0xFFA32D2D));
}

// ─────────────────────────────────────────────────────────────────────────────
// AYLIK GENEL BAKIŞ
// ─────────────────────────────────────────────────────────────────────────────
class CalendarMonthOverview extends StatefulWidget {
  const CalendarMonthOverview({super.key, this.fixedHomeAddress});
  final Address? fixedHomeAddress;

  @override
  State<CalendarMonthOverview> createState() => _CalendarMonthOverviewState();
}

class _CalendarMonthOverviewState extends State<CalendarMonthOverview> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  int _countForDay(
    Map<DateTime, Map<ShiftType, List<VisitPlanItem>>> planByDay,
    DateTime day,
  ) {
    final key = DateTime(day.year, day.month, day.day);
    final dayMap = planByDay[key];
    if (dayMap == null) return 0;
    var total = 0;
    for (final list in dayMap.values) {
      total += list.length;
    }
    return total;
  }

  void _openDay(DateTime day) {
    context.push(
      '/calendar/day',
      extra: CalendarDayRouteArgs(day: day, fixedHomeAddress: widget.fixedHomeAddress),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetState>();
    final planByDay = fleet.activeWorkspace?.planByDay ?? const {};
    final now = DateTime.now();

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday - 1;
    final monthLabel = '${_monthNames[_month.month]} ${_month.year}';

    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          // ── Araç seçici ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: VehicleSelectorBar()),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fleet.activeWorkspace?.driver.label ?? '—',
                      style: const TextStyle(
                        color: _C.textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Aktif sürücü takvimi',
                      style: TextStyle(
                        color: _C.textLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Üst bar: geri, başlık, ay gezinme ───────────────────────────
          Container(
            color: _C.sidebar,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Aylık Takvim',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _changeMonth(-1),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    monthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _changeMonth(1),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Ay ızgarası ──────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                children: [
                  Row(
                    children: _weekdayShort
                        .map(
                          (d) => Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: const TextStyle(
                                  color: _C.textLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: leadingBlanks + daysInMonth,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1.1,
                    ),
                    itemBuilder: (context, index) {
                      if (index < leadingBlanks) return const SizedBox.shrink();
                      final dayNum = index - leadingBlanks + 1;
                      final date = DateTime(_month.year, _month.month, dayNum);
                      final count = _countForDay(planByDay, date);
                      final band = _densityFor(count);
                      final isToday = _isSameDay(date, now);

                      return InkWell(
                        onTap: () => _openDay(date),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: band.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: isToday
                                ? Border.all(color: _C.accent, width: 1.5)
                                : Border.all(color: _C.stroke, width: 0.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dayNum',
                                style: TextStyle(
                                  color: count > 0 ? band.fg : _C.textMid,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (count > 0)
                                Text(
                                  '$count',
                                  style: TextStyle(
                                    color: band.fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Yoğunluk',
                        style: TextStyle(color: _C.textLight, fontSize: 11),
                      ),
                      _LegendDot(color: _C.surface, label: '0', bordered: true),
                      _LegendDot(color: _densityFor(3).bg, label: '1–5'),
                      _LegendDot(color: _densityFor(8).bg, label: '6–10'),
                      _LegendDot(color: _densityFor(13).bg, label: '11–15'),
                      _LegendDot(color: _densityFor(18).bg, label: '16–20'),
                    ],
                  ),
                ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.bordered = false,
  });
  final Color color;
  final String label;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: bordered ? Border.all(color: _C.stroke) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: _C.textMid, fontSize: 11),
        ),
      ],
    );
  }
}
