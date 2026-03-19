import 'package:flutter/material.dart';
import '../services/reports_page.dart';

class SavedRoutesPage extends StatefulWidget {
  const SavedRoutesPage({super.key});

  @override
  State<SavedRoutesPage> createState() => _SavedRoutesPageState();
}

class _SavedRoutesPageState extends State<SavedRoutesPage> {
  static const _bg = Color(0xFF0B1018);
  static const _surface = Color(0xFF141B26);
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _accentNav = Color(0xFF1A3A5C);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);
  static const _green = Color(0xFF2ECC71);
  static const _orange = Color(0xFFFFB74D);

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtDur(int min) {
    if (min < 60) return '$min dk';
    return '${min ~/ 60}s ${min % 60}dk';
  }

  @override
  Widget build(BuildContext context) {
    final records = RouteStore.instance.allRecords;

    return Scaffold(
      backgroundColor: _bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Row(
              children: [
                const Icon(Icons.route_rounded, color: _accent, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Oluşturulan Rotalar',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent.withOpacity(0.25)),
                  ),
                  child: Text(
                    '${records.length} rota',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Liste
            Expanded(
              child: records.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final r = records[index];
                        final routeNo = records.length - index;
                        return _RouteCard(
                          record: r,
                          routeNo: routeNo,
                          fmtDate: _fmtDate,
                          fmtDur: _fmtDur,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_rounded, size: 56, color: _textLight.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text(
            'Henüz rota oluşturulmadı',
            style: TextStyle(
              color: _textLight,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rota Paneli\'nden rota oluşturun,\nburada otomatik görünür.',
            style: TextStyle(color: Color(0xFF3D4D60), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatefulWidget {
  final RouteRecord record;
  final int routeNo;
  final String Function(DateTime) fmtDate;
  final String Function(int) fmtDur;

  const _RouteCard({
    required this.record,
    required this.routeNo,
    required this.fmtDate,
    required this.fmtDur,
  });

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _expanded = false;

  static const _surface = Color(0xFF141B26);
  static const _surface2 = Color(0xFF1A2333);
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _accentNav = Color(0xFF1A3A5C);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);
  static const _green = Color(0xFF2ECC71);
  static const _orange = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        children: [
          // ── Başlık satırı ───────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(16))
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Numara
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '#${widget.routeNo}',
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Tarih & araç
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rota #${widget.routeNo}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.fmtDate(r.createdAt),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stat chips
                  _StatChip(
                    label: widget.fmtDur(r.totalMin),
                    icon: Icons.timer_rounded,
                    color: _accent,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: '${r.totalKm.toStringAsFixed(1)} km',
                    icon: Icons.route_rounded,
                    color: _green,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: '${r.stopCount} durak',
                    icon: Icons.pin_drop_rounded,
                    color: _orange,
                  ),
                  const SizedBox(width: 12),

                  // Expand ikonu
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Detay (genişletince) ─────────────────────────────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.alt_route_rounded, size: 14, color: _textLight),
                      SizedBox(width: 6),
                      Text(
                        'Rota Sırası',
                        style: TextStyle(
                          color: _textLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...r.path.asMap().entries.map((e) {
                    final idx = e.key;
                    final addr = e.value;
                    final isFirst = idx == 0;
                    final isLast = idx == r.path.length - 1;
                    final isMiddle = !isFirst && !isLast;

                    Color dotColor = _textLight;
                    IconData dotIcon = Icons.circle;
                    if (isFirst) {
                      dotColor = _green;
                      dotIcon = Icons.home_rounded;
                    } else if (isLast) {
                      dotColor = _accentNav;
                      dotIcon = Icons.flag_rounded;
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sol: ikon + çizgi
                        SizedBox(
                          width: 32,
                          child: Column(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: dotColor.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: dotColor.withOpacity(0.4),
                                  ),
                                ),
                                child: Icon(dotIcon, size: 14, color: dotColor),
                              ),
                              if (!isLast)
                                Container(
                                  width: 2,
                                  height: 28,
                                  color: _stroke,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Sağ: numara + adres
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: dotColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isFirst
                                            ? 'Başlangıç'
                                            : isLast
                                                ? 'Bitiş'
                                                : 'Durak $idx',
                                        style: TextStyle(
                                          color: dotColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  addr,
                                  style: const TextStyle(
                                    color: _textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}