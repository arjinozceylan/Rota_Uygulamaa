import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reports_page.dart';

/// Tek bir durağın görüntülenme modeli — hem backend'den hem yerel
/// depodan gelen veriyi ortak bir şekle çevirmek için kullanılır.
class _StopView {
  final String address;
  final bool completed;
  const _StopView({required this.address, required this.completed});
}

/// Tek bir rotanın görüntülenme modeli.
class _RouteView {
  final String name;
  final DateTime createdAt;
  final double totalKm;
  final int totalMin;
  final List<_StopView> stops;

  const _RouteView({
    required this.name,
    required this.createdAt,
    required this.totalKm,
    required this.totalMin,
    required this.stops,
  });

  int get completedCount => stops.where((s) => s.completed).length;
}

class SavedRoutesPage extends StatefulWidget {
  const SavedRoutesPage({super.key});

  @override
  State<SavedRoutesPage> createState() => _SavedRoutesPageState();
}

class _SavedRoutesPageState extends State<SavedRoutesPage> {
  static const _bg = Color(0xFF0B1018);
  static const _accent = Color(0xFF53D6FF);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);

  static const String _baseUrl = 'https://route-backend-jeu7.onrender.com';

  bool _loading = true;
  String? _error;
  List<_RouteView> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtDur(int min) {
    if (min < 60) return '$min dk';
    return '${min ~/ 60}s ${min % 60}dk';
  }

  List<_RouteView> _fromLocalRecords() {
    return RouteStore.instance.allRecords
        .map(
          (r) => _RouteView(
            name: 'Rota (Cihazda)',
            createdAt: r.createdAt,
            totalKm: r.totalKm,
            totalMin: r.totalMin,
            // Yerel kayıtlarda tamamlanma bilgisi tutulmuyor.
            stops: r.path
                .map((addr) => _StopView(address: addr, completed: false))
                .toList(),
          ),
        )
        .toList();
  }

  _RouteView _fromBackendJson(Map<String, dynamic> route) {
    final routeJson = route['route_json'] as Map<String, dynamic>? ?? {};
    final stopsRaw = routeJson['stops'] as List? ?? const [];
    final sorted = stopsRaw.map((e) => e as Map<String, dynamic>).toList()
      ..sort(
        (a, b) => ((a['order'] ?? 0) as num).compareTo((b['order'] ?? 0) as num),
      );

    final stops = sorted.map((s) {
      final addr = (s['address'] ?? s['street'] ?? '').toString();
      final completed = s['completed'] == true;
      return _StopView(address: addr, completed: completed);
    }).toList();

    final createdAtRaw = route['created_at']?.toString();
    final createdAt = DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now();

    final totalKm = (routeJson['totalKm'] as num?)?.toDouble() ?? 0.0;
    final totalMin = (routeJson['totalMin'] as num?)?.toInt() ?? 0;

    return _RouteView(
      name: (route['name'] ?? 'Rota').toString(),
      createdAt: createdAt,
      totalKm: totalKm,
      totalMin: totalMin,
      stops: stops,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) {
        // Misafir modu: backend'de kullanıcıya bağlı rota yok, cihazdakini göster.
        _routes = _fromLocalRecords();
      } else {
        final res = await http.get(Uri.parse('$_baseUrl/routes/$userId'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as List;
          _routes = data
              .map((r) => _fromBackendJson(r as Map<String, dynamic>))
              .toList();
        } else {
          _error = 'Rotalar sunucudan alınamadı (kod ${res.statusCode}).';
          _routes = _fromLocalRecords();
        }
      }
    } catch (e) {
      _error = 'Rotalar yüklenirken bir hata oluştu, cihazdaki kayıtlar gösteriliyor.';
      _routes = _fromLocalRecords();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(width: 10),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, color: _accent),
                  tooltip: 'Yenile',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent.withOpacity(0.25)),
                  ),
                  child: Text(
                    '${_routes.length} rota',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Liste
            Expanded(
              child: _loading && _routes.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent),
                    )
                  : _routes.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          itemCount: _routes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final r = _routes[index];
                            final routeNo = index + 1;
                            return _RouteCard(
                              route: r,
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
  final _RouteView route;
  final int routeNo;
  final String Function(DateTime) fmtDate;
  final String Function(int) fmtDur;

  const _RouteCard({
    required this.route,
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
  static const _stroke = Color(0xFF1E2A3A);
  static const _accent = Color(0xFF53D6FF);
  static const _accentNav = Color(0xFF1A3A5C);
  static const _textDark = Color(0xFFE8EDF3);
  static const _textLight = Color(0xFF6B7A8D);
  static const _green = Color(0xFF2ECC71);
  static const _orange = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final total = r.stops.length;
    final done = r.completedCount;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        children: [
          // ── Başlık satırı ──────────────────────────────────────────
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
                    label: '$done/$total tamamlandı',
                    icon: Icons.check_circle_outline_rounded,
                    color: done == total && total > 0 ? _green : _orange,
                  ),
                  const SizedBox(width: 12),

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

          // ── Detay (genişletince) ────────────────────────────────────
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
                  ...r.stops.asMap().entries.map((e) {
                    final idx = e.key;
                    final stop = e.value;
                    final isFirst = idx == 0;
                    final isLast = idx == r.stops.length - 1;

                    Color dotColor = _textLight;
                    IconData dotIcon = Icons.circle_outlined;

                    if (stop.completed) {
                      dotColor = _green;
                      dotIcon = Icons.check_rounded;
                    } else if (isFirst) {
                      dotColor = _green;
                      dotIcon = Icons.home_rounded;
                    } else if (isLast) {
                      dotColor = _accentNav;
                      dotIcon = Icons.flag_rounded;
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                    if (stop.completed) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _green.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Tamamlandı',
                                          style: TextStyle(
                                            color: _green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  stop.address,
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