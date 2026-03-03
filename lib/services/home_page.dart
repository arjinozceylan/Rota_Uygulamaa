import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/models/address.dart';
import '../data/address_store.dart';
import '../models/calendar_event.dart';
import '../screens/map_picker_page.dart';
import '../screens/osm_places_service.dart';
import '../screens/calendar_page.dart';
import 'osrm_route_service.dart';
import 'reports_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class _T {
  static const bg = Color(0xFFF0F4F8);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFF1A2236);
  static const sidebarSel = Color(0xFF253150);
  static const accent = Color(0xFF53D6FF);
  static const accentRed = Color(0xFFE53935);
  static const textDark = Color(0xFF1A2236);
  static const textMid = Color(0xFF5A6A85);
  static const textLight = Color(0xFF9DAFC8);
  static const stroke = Color(0xFFE2E8F0);
  static const strokeMid = Color(0xFFCDD5E0);
  static const searchBg = Color(0xFFF7FAFF);
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV ITEM
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// ROTA ALGORİTMASI (orijinalden aynen kopyalandı — değiştirilmedi)
// ─────────────────────────────────────────────────────────────────────────────
double _durMin(OsrmMatrix m, int i, int j) {
  final v = m.durationsSeconds[i][j];
  if (v == null) return 1e15;
  return v / 60.0;
}

double _distKm(OsrmMatrix m, int i, int j) {
  final v = m.distancesMeters[i][j];
  if (v == null) return 1e15;
  return v / 1000.0;
}

double _tourCostIdxMin(OsrmMatrix m, List<int> path) {
  double sum = 0;
  for (int k = 0; k < path.length - 1; k++) {
    sum += _durMin(m, path[k], path[k + 1]);
  }
  return sum;
}

double _tourCostIdxKm(OsrmMatrix m, List<int> path) {
  double sum = 0;
  for (int k = 0; k < path.length - 1; k++) {
    sum += _distKm(m, path[k], path[k + 1]);
  }
  return sum;
}

List<int> _nearestNeighborTourIdx(OsrmMatrix m, int startIdx) {
  final n = m.n;
  final unvisited = <int>{};
  for (int i = 0; i < n; i++) {
    if (i != startIdx) unvisited.add(i);
  }
  final route = <int>[startIdx];
  int current = startIdx;
  while (unvisited.isNotEmpty) {
    int best = -1;
    double bestCost = 1e15;
    for (final cand in unvisited) {
      final c = _durMin(m, current, cand);
      if (c < bestCost) {
        bestCost = c;
        best = cand;
      }
    }
    route.add(best);
    unvisited.remove(best);
    current = best;
  }
  route.add(startIdx);
  return route;
}

List<int> _twoOptIdx(OsrmMatrix m, List<int> path) {
  if (path.length <= 4) return path;
  bool improved = true;
  List<int> best = List<int>.from(path);
  double bestCost = _tourCostIdxMin(m, best);
  while (improved) {
    improved = false;
    for (int i = 1; i < best.length - 2; i++) {
      for (int k = i + 1; k < best.length - 1; k++) {
        final candidate = <int>[
          ...best.sublist(0, i),
          ...best.sublist(i, k + 1).reversed,
          ...best.sublist(k + 1),
        ];
        final candCost = _tourCostIdxMin(m, candidate);
        if (candCost < bestCost) {
          best = candidate;
          bestCost = candCost;
          improved = true;
        }
      }
    }
  }
  return best;
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME PAGE
// ─────────────────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int maxDaily = 20;

  // ── Nav ──────────────────────────────────────────────────────────────────
  int _navIndex = 0;
  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Rota Paneli'),
    _NavItem(icon: Icons.table_chart_rounded, label: 'Excel Yükle'),
    _NavItem(icon: Icons.folder_copy_rounded, label: 'Excel Yüklenleri'),
    _NavItem(icon: Icons.calendar_month_rounded, label: 'Takvim'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Raporlar'),
  ];

  // ── Mod ──────────────────────────────────────────────────────────────────
  bool _mapMode = true; // true = Haritadan Seç, false = Elle Yaz

  // ── Arama ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _manualCtrl = TextEditingController();
  final OsmPlacesService _placesService = const OsmPlacesService();
  final OsrmRouteService _osrm = const OsrmRouteService();
  Timer? _searchDebounce;
  int _latestSearchId = 0;
  bool _isSearching = false;
  List<Address> _suggestions = [];

  // ── Adres havuzu + rota kuyruğu ──────────────────────────────────────────
  // addressCards: sol paneldeki sürüklenebilir kartlar
  final List<String> addressCards = [];
  // dropped: sağ panele (rota kuyruğuna) eklenmiş adresler — OSRM buradan çalışır
  final List<String> dropped = [];
  final Map<String, RepeatType> repeatByAddress = {};

  // Başlangıç adresi
  String? selectedStartAddress;

  // Sayaçlar
  int _mapPickCodeCounter = 1;
  int _manualCodeCounter = 1;

  // ── Sidebar özet — rota sonrası güncellenir ───────────────────────────────
  int _summaryTransferCount = 0;
  int _summaryTotalMin = 0;
  double _summaryTotalKm = 0;
  bool _summaryHasData = false;

  // ── Arama geçmişi (son 5) ────────────────────────────────────────────────
  final List<String> _searchHistory = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    for (final a in AddressStore.items) {
      final text = a.address;
      if (!addressCards.contains(text)) addressCards.insert(0, text);
    }
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Arama ────────────────────────────────────────────────────────────────
  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final searchId = ++_latestSearchId;
      final query = _searchCtrl.text.trim();
      if (query.isEmpty) {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _isSearching = false;
        });
        return;
      }
      final results = await _placesService.search(query: query);
      if (!mounted || searchId != _latestSearchId) return;
      setState(() {
        _suggestions = results;
        _isSearching = false;
        // Arama geçmişine ekle (duplicate ve boş kontrolü)
        if (results.isNotEmpty && !_searchHistory.contains(query)) {
          _searchHistory.insert(0, query);
          if (_searchHistory.length > 5) _searchHistory.removeLast();
        }
      });
    });
  }

  // ── Adres ekleme ─────────────────────────────────────────────────────────
  Address _makeMapPickedAddress(MapPickResult res) {
    final code = 'P${(_mapPickCodeCounter++).toString().padLeft(3, '0')}';
    return Address(
      code: code,
      address: res.label,
      placeId:
          'osm:${res.point.latitude.toStringAsFixed(6)},${res.point.longitude.toStringAsFixed(6)}',
      lat: res.point.latitude,
      lng: res.point.longitude,
    );
  }

  Address _makeManualAddress(String text) {
    final t = text.trim();
    return Address(
      code: 'M${(_manualCodeCounter++).toString().padLeft(3, '0')}',
      address: t,
      placeId: 'manual:$t',
      lat: null,
      lng: null,
    );
  }

  void _addAddressToPoolAndCards(Address addressObj) {
    final a = addressObj.address.trim();
    if (a.isEmpty) return;
    setState(() {
      AddressStore.add(addressObj);
      if (!addressCards.contains(a)) addressCards.insert(0, a);
    });
  }

  Future<void> _openMapPicker() async {
    final res = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerPage()),
    );
    if (!mounted || res == null) return;
    _addAddressToPoolAndCards(_makeMapPickedAddress(res));
    setState(() {
      _suggestions = [];
      _searchCtrl.clear();
    });
  }

  void _addManualAddress() {
    final text = _manualCtrl.text.trim();
    if (text.isEmpty) return;
    _addAddressToPoolAndCards(_makeManualAddress(text));
    setState(() => _manualCtrl.clear());
  }

  // ── Rota kuyruğuna ekle ──────────────────────────────────────────────────
  void _dropAddress(String value) {
    if (dropped.length >= maxDaily) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Günlük limit dolu (20).')));
      return;
    }
    if (!dropped.contains(value)) {
      setState(() {
        dropped.add(value);
        if (selectedStartAddress != null &&
            !dropped.contains(selectedStartAddress)) {
          selectedStartAddress = null;
        }
      });
    }
  }

  void _removeFromQueue(String value) {
    setState(() {
      dropped.remove(value);
      if (selectedStartAddress == value) selectedStartAddress = null;
    });
  }

  void _clearQueue() {
    setState(() {
      dropped.clear();
      repeatByAddress.clear();
      selectedStartAddress = null;
    });
  }

  // ── CSV import ────────────────────────────────────────────────────────────
  Future<void> _importAddressesFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dosya yolu bulunamadı')));
        return;
      }
      final bytes = await File(path).readAsBytes();
      final text = utf8.decode(bytes);
      final lines = const LineSplitter().convert(text);
      if (lines.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('CSV boş')));
        return;
      }
      final header = lines.first;
      final commaCount = ','.allMatches(header).length;
      final semiCount = ';'.allMatches(header).length;
      final sep = semiCount > commaCount ? ';' : ',';
      int added = 0;
      for (final line in lines) {
        final raw = line.trim();
        if (raw.isEmpty) continue;
        final firstCol = raw.split(sep).first.trim();
        if (firstCol.isEmpty) continue;
        if (firstCol.toLowerCase() == 'adres') continue;
        _addAddressToPoolAndCards(_makeManualAddress(firstCol));
        added++;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $added adres CSV\'den yüklendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV yükleme hatası: $e')));
    }
  }

  // ── ROTA OLUŞTUR (orijinalden aynen — değiştirilmedi) ────────────────────
  Future<void> _runDemoRoute() async {
    if (dropped.isEmpty) return;

    final Map<String, Address> byText = {
      for (final a in AddressStore.items) a.address: a,
    };

    final stops = <Address>[];
    for (final txt in dropped) {
      final a = byText[txt];
      if (a == null) continue;
      if (a.lat == null || a.lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${a.address}" için koordinat yok. Haritadan seç / suggestion ile ekle.',
            ),
          ),
        );
        return;
      }
      stops.add(a);
    }

    if (stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota için en az 2 koordinatlı adres gerekli.'),
        ),
      );
      return;
    }

    Address start;
    if (selectedStartAddress != null) {
      final s = byText[selectedStartAddress!];
      if (s == null || s.lat == null || s.lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seçili başlangıç adresi geçersiz.')),
        );
        return;
      }
      start = s;
    } else {
      start = stops.first;
    }

    final nodes = <Address>[start];
    for (final s in stops) {
      if (s.address == start.address) continue;
      nodes.add(s);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 64,
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text('Gerçek süre/mesafe hesaplanıyor (OSRM)...'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final matrix = await _osrm.table(
        coords: nodes
            .map((a) => LatLng(a.lat!, a.lng!))
            .toList(growable: false),
      );

      final idxRoute = _nearestNeighborTourIdx(matrix, 0);
      final improved = _twoOptIdx(matrix, idxRoute);

      final totalMin = _tourCostIdxMin(matrix, improved).round();
      final totalKm = _tourCostIdxKm(matrix, improved);
      final path = improved.map((i) => nodes[i].address).toList();

      if (!mounted) return;
      Navigator.pop(context);

      // ── Sidebar özet güncelle + RouteStore'a kaydet ──────────────────────
      RouteStore.instance.add(
        RouteRecord(
          createdAt: DateTime.now(),
          totalMin: totalMin,
          totalKm: totalKm,
          path: path,
        ),
      );
      setState(() {
        _summaryTransferCount = path.length - 1;
        _summaryTotalMin = totalMin;
        _summaryTotalKm = totalKm;
        _summaryHasData = true;
      });

      showDialog(
        context: context,
        builder: (_) => _RouteResultDialog(
          totalMin: totalMin,
          totalKm: totalKm,
          path: path,
          hasAutoStart: selectedStartAddress == null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OSRM hata: $e')));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (selectedStartAddress != null &&
        !dropped.contains(selectedStartAddress)) {
      selectedStartAddress = null;
    }

    return Scaffold(
      backgroundColor: _T.bg,
      body: Row(
        children: [
          // ── Sol kenar çubuğu ────────────────────────────────────────────
          _Sidebar(
            navItems: _navItems,
            selectedIndex: _navIndex,
            summaryHasData: _summaryHasData,
            summaryTransferCount: _summaryTransferCount,
            summaryTotalMin: _summaryTotalMin,
            summaryTotalKm: _summaryTotalKm,
            onSelect: (i) {
              if (i == 1) {
                _importAddressesFromExcel();
                return;
              }
              if (i == 3) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CalendarPage()),
                ).then(
                  (_) => setState(() {
                    for (final a in AddressStore.items) {
                      if (!addressCards.contains(a.address))
                        addressCards.insert(0, a.address);
                    }
                  }),
                );
                return;
              }
              if (i == 4) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
                return;
              }
              setState(() => _navIndex = i);
            },
          ),

          // ── Ana içerik ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // Mod geçiş butonları
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      _ModeToggleButton(
                        label: 'Haritadan Seç',
                        icon: Icons.map_rounded,
                        selected: _mapMode,
                        color: const Color(0xFF3DBFDB),
                        onTap: () => setState(() => _mapMode = true),
                      ),
                      const SizedBox(width: 10),
                      _ModeToggleButton(
                        label: 'Elle Yaz',
                        icon: Icons.keyboard_rounded,
                        selected: !_mapMode,
                        color: _T.accentRed,
                        onTap: () => setState(() => _mapMode = false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // İki sütun
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sol: Adres Arama Paneli
                        Expanded(
                          flex: 3,
                          child: _SearchPanel(
                            mapMode: _mapMode,
                            searchCtrl: _searchCtrl,
                            manualCtrl: _manualCtrl,
                            isSearching: _isSearching,
                            suggestions: _suggestions,
                            searchHistory: _searchHistory,
                            showHistory: _showHistory,
                            addressCards: addressCards,
                            dropped: dropped,
                            onOpenMap: _openMapPicker,
                            onAddManual: _addManualAddress,
                            onToggleHistory: () =>
                                setState(() => _showHistory = !_showHistory),
                            onHistorySelect: (q) {
                              _searchCtrl.text = q;
                              setState(() => _showHistory = false);
                              _onSearchChanged();
                            },
                            onAddSuggestion: (addr) {
                              _addAddressToPoolAndCards(addr);
                              _dropAddress(addr.address);
                              setState(() {
                                _suggestions = [];
                                _searchCtrl.clear();
                                _showHistory = false;
                              });
                            },
                            onDropAddress: _dropAddress,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Sağ: Rota Kuyruğu
                        SizedBox(
                          width: 280,
                          child: _QueuePanel(
                            dropped: dropped,
                            addressCards: addressCards,
                            selectedStartAddress: selectedStartAddress,
                            onStartSelected: (v) =>
                                setState(() => selectedStartAddress = v),
                            onRemove: _removeFromQueue,
                            onAcceptDrop: _dropAddress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Alt çubuk
                _BottomBar(
                  hasItems: dropped.isNotEmpty,
                  onClear: _clearQueue,
                  onCreateRoute: _runDemoRoute,
                  droppedCount: dropped.length,
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
// SIDEBAR
// ─────────────────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.navItems,
    required this.selectedIndex,
    required this.onSelect,
    required this.summaryHasData,
    required this.summaryTransferCount,
    required this.summaryTotalMin,
    required this.summaryTotalKm,
  });
  final List<_NavItem> navItems;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool summaryHasData;
  final int summaryTransferCount, summaryTotalMin;
  final double summaryTotalKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: _T.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _T.accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _T.accent.withOpacity(0.35)),
                  ),
                  child: const Center(
                    child: Text(
                      'RD',
                      style: TextStyle(
                        color: _T.accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'rota_desktop',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _T.accentRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_location_alt_rounded,
                      color: _T.accentRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adres Havuzu',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: _T.accentRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'ÇEVRİMDİŞİ MOD',
                            style: TextStyle(
                              color: _T.accentRed,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: navItems.length,
              itemBuilder: (_, i) {
                final item = navItems[i];
                final sel = i == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _T.sidebarSel : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 18,
                            color: sel
                                ? Colors.white
                                : Colors.white.withOpacity(0.55),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.55),
                              fontWeight: sel
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Günlük Transfer Özeti ─────────────────────────────────────
          _TransferSummaryCard(
            hasData: summaryHasData,
            transferCount: summaryTransferCount,
            totalMin: summaryTotalMin,
            totalKm: summaryTotalKm,
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _T.accent.withOpacity(0.15),
                  child: const Icon(
                    Icons.person_rounded,
                    color: _T.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operations Manager',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Sürüm v2.4.0',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 11,
                        ),
                      ),
                    ],
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
// MODE TOGGLE
// ─────────────────────────────────────────────────────────────────────────────
class _ModeToggleButton extends StatelessWidget {
  const _ModeToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color : _T.stroke,
            width: selected ? 0 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : _T.textMid),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _T.textMid,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.mapMode,
    required this.searchCtrl,
    required this.manualCtrl,
    required this.isSearching,
    required this.suggestions,
    required this.searchHistory,
    required this.showHistory,
    required this.addressCards,
    required this.dropped,
    required this.onOpenMap,
    required this.onAddManual,
    required this.onToggleHistory,
    required this.onHistorySelect,
    required this.onAddSuggestion,
    required this.onDropAddress,
  });

  final bool mapMode;
  final TextEditingController searchCtrl, manualCtrl;
  final bool isSearching;
  final List<Address> suggestions;
  final List<String> searchHistory, addressCards, dropped;
  final bool showHistory;
  final VoidCallback onOpenMap, onAddManual, onToggleHistory;
  final ValueChanged<String> onHistorySelect;
  final ValueChanged<Address> onAddSuggestion;
  final ValueChanged<String> onDropAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _T.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Adres Arama Paneli',
                  style: TextStyle(
                    color: _T.textDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (mapMode)
                  TextButton.icon(
                    onPressed: onOpenMap,
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('Haritayı Aç'),
                    style: TextButton.styleFrom(
                      foregroundColor: _T.accent,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Arama / elle yazma alanı
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: mapMode
                ? _SearchBar(
                    ctrl: searchCtrl,
                    isSearching: isSearching,
                    hasHistory: searchHistory.isNotEmpty,
                    onHistoryTap: onToggleHistory,
                  )
                : _ManualBar(ctrl: manualCtrl, onAdd: onAddManual),
          ),

          // Geçmiş aramalar dropdown
          if (mapMode && showHistory && searchHistory.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _T.stroke),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.history_rounded,
                            size: 13,
                            color: _T.textLight,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Son Aramalar',
                            style: TextStyle(
                              color: _T.textLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _T.stroke),
                    ...searchHistory.map(
                      (q) => InkWell(
                        onTap: () => onHistorySelect(q),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: _T.textLight,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  q,
                                  style: const TextStyle(
                                    color: _T.textDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.north_west_rounded,
                                size: 13,
                                color: _T.textLight,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

          // Suggestion listesi
          if (suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: _T.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _T.stroke),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: _T.stroke,
                    indent: 14,
                    endIndent: 14,
                  ),
                  itemBuilder: (_, i) {
                    final addr = suggestions[i];
                    return InkWell(
                      onTap: () => onAddSuggestion(addr),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 16,
                              color: _T.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                addr.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _T.textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.add_circle_rounded,
                              size: 18,
                              color: _T.accent,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: _T.stroke, height: 1),
          ),
          const SizedBox(height: 8),

          // Adres kartları (sürüklenebilir)
          Expanded(
            child: addressCards.isEmpty
                ? const Center(
                    child: Text(
                      'Henüz adres eklenmedi',
                      style: TextStyle(
                        color: _T.textLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: addressCards.length,
                    itemBuilder: (_, i) {
                      final text = addressCards[i];
                      final inQueue = dropped.contains(text);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Draggable<String>(
                          data: text,
                          feedback: Material(
                            color: Colors.transparent,
                            child: _DraggingChip(text: text),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: _AddressRow(text: text, inQueue: inQueue),
                          ),
                          child: GestureDetector(
                            onTap: () => onDropAddress(text),
                            child: _AddressRow(text: text, inQueue: inQueue),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.ctrl,
    required this.isSearching,
    required this.hasHistory,
    required this.onHistoryTap,
  });
  final TextEditingController ctrl;
  final bool isSearching, hasHistory;
  final VoidCallback onHistoryTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _T.searchBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.stroke),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: _T.textLight, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                color: _T.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: 'Haritadan adres ara',
                hintStyle: TextStyle(color: _T.textLight, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (isSearching)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _T.accent,
                ),
              ),
            ),
          // Geçmiş butonu
          if (hasHistory && !isSearching)
            GestureDetector(
              onTap: onHistoryTap,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Son aramalar',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _T.accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 15,
                      color: _T.accent,
                    ),
                  ),
                ),
              ),
            ),
          _ProviderBadge(label: 'G', color: const Color(0xFF4285F4)),
          const SizedBox(width: 6),
          _ProviderBadge(label: 'Y', color: const Color(0xFFFF0000)),
          const SizedBox(width: 6),
          _ProviderBadge(label: 'H', color: const Color(0xFF00B0F0)),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _ManualBar extends StatelessWidget {
  const _ManualBar({required this.ctrl, required this.onAdd});
  final TextEditingController ctrl;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: _T.searchBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.stroke),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.edit_rounded, color: _T.textLight, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => onAdd(),
              style: const TextStyle(
                color: _T.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: 'Elle adres girin…',
                hintStyle: TextStyle(color: _T.textLight, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _T.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Ekle',
                style: TextStyle(
                  color: _T.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.text, required this.inQueue});
  final String text;
  final bool inQueue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: inQueue ? _T.accent.withOpacity(0.06) : _T.searchBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inQueue ? _T.accent.withOpacity(0.35) : _T.stroke,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 18,
            color: inQueue ? _T.accent : _T.textLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: inQueue ? _T.textDark : _T.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          Icon(
            inQueue
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            size: 18,
            color: inQueue ? _T.accent : _T.textLight,
          ),
        ],
      ),
    );
  }
}

class _DraggingChip extends StatelessWidget {
  const _DraggingChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.accent.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_rounded, size: 16, color: _T.accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _T.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUEUE PANEL (sağ kolon — DragTarget)
// ─────────────────────────────────────────────────────────────────────────────
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.dropped,
    required this.addressCards,
    required this.selectedStartAddress,
    required this.onStartSelected,
    required this.onRemove,
    required this.onAcceptDrop,
  });

  final List<String> dropped, addressCards;
  final String? selectedStartAddress;
  final ValueChanged<String?> onStartSelected;
  final ValueChanged<String> onRemove, onAcceptDrop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _T.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seçili Adresler',
                        style: TextStyle(
                          color: _T.textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'ROTA KUYRUĞU',
                        style: TextStyle(
                          color: _T.textLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                _CountBadge(count: dropped.length, color: _T.accent),
              ],
            ),
          ),
          const Divider(color: _T.stroke, height: 1),

          Expanded(
            child: DragTarget<String>(
              onWillAccept: (_) => true,
              onAccept: onAcceptDrop,
              builder: (context, candidateData, rejectedData) {
                final isDraggingOver = candidateData.isNotEmpty;
                if (dropped.isEmpty) {
                  return _EmptyQueueState(isDraggingOver: isDraggingOver);
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: dropped.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final addr = dropped[i];
                    final isStart = addr == selectedStartAddress;
                    // Animasyonlu giriş: her kart kendi index'ine göre gecikmeyle kayar
                    return _AnimatedQueueItem(
                      key: ValueKey(addr),
                      index: i,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isStart
                              ? const Color(0xFFE8F5E9)
                              : _T.searchBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isStart
                                ? Colors.green.withOpacity(0.4)
                                : _T.stroke,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isStart ? Colors.green : _T.accent)
                                  .withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Animasyonlu sıra numarası
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                gradient: isStart
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF66BB6A),
                                          Color(0xFF43A047),
                                        ],
                                      )
                                    : LinearGradient(
                                        colors: [
                                          _T.accent,
                                          const Color(0xFF3DBFDB),
                                        ],
                                      ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isStart ? Colors.green : _T.accent)
                                        .withOpacity(0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: isStart
                                    ? const Icon(
                                        Icons.flag_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      )
                                    : Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                addr,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _T.textDark,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  onStartSelected(isStart ? null : addr),
                              child: Tooltip(
                                message: isStart
                                    ? 'Başlangıç kaldır'
                                    : 'Başlangıç yap',
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isStart
                                        ? Colors.green.withOpacity(0.12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.flag_rounded,
                                    size: 15,
                                    color: isStart
                                        ? Colors.green
                                        : _T.textLight,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: () => onRemove(addr),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _T.accentRed.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: _T.accentRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY QUEUE STATE — animasyonlu modern boş durum
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// ANİMASYONLU KUYRUK ITEM — sürükleme sonrası kayarak giriş
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedQueueItem extends StatefulWidget {
  const _AnimatedQueueItem({
    super.key,
    required this.index,
    required this.child,
  });
  final int index;
  final Widget child;

  @override
  State<_AnimatedQueueItem> createState() => _AnimatedQueueItemState();
}

class _AnimatedQueueItemState extends State<_AnimatedQueueItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    // Her item index'ine göre farklı gecikme — sıralı animasyon hissi
    final delay = widget.index * 40;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _ctrl.forward();
    });

    _slide = Tween<double>(
      begin: 30,
      end: 0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(_slide.value, 0),
        child: Opacity(opacity: _fade.value, child: child),
      ),
      child: widget.child,
    );
  }
}

class _EmptyQueueState extends StatefulWidget {
  const _EmptyQueueState({required this.isDraggingOver});
  final bool isDraggingOver;

  @override
  State<_EmptyQueueState> createState() => _EmptyQueueStateState();
}

class _EmptyQueueStateState extends State<_EmptyQueueState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _float = Tween<double>(
      begin: -6,
      end: 6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragging = widget.isDraggingOver;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: dragging
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _T.accent.withOpacity(0.08),
                  const Color(0xFF3DBFDB).withOpacity(0.04),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFFF7FAFF), const Color(0xFFEEF4FB)],
              ),
        border: Border.all(
          color: dragging ? _T.accent : _T.stroke,
          width: dragging ? 2 : 1.5,
        ),
      ),
      child: Center(
        child: dragging
            ? _DropHereState()
            : _IdleEmptyState(float: _float, pulse: _pulse),
      ),
    );
  }
}

class _IdleEmptyState extends StatelessWidget {
  const _IdleEmptyState({required this.float, required this.pulse});
  final Animation<double> float, pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: float,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, float.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Harita illüstrasyonu
              _MapIllustration(pulse: pulse),
              const SizedBox(height: 20),

              // Başlık
              const Text(
                'Henüz Adres Seçilmedi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _T.textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sol taraftan adres ekle\nveya sürükleyip buraya bırak',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _T.textLight,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // İpucu rozetleri
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HintBadge(icon: Icons.touch_app_rounded, label: 'Tıkla'),
                  const SizedBox(width: 8),
                  _HintBadge(
                    icon: Icons.drag_indicator_rounded,
                    label: 'Sürükle',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropHereState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _T.accent.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: _T.accent.withOpacity(0.4), width: 2),
          ),
          child: const Icon(
            Icons.add_location_alt_rounded,
            size: 30,
            color: _T.accent,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Bırak!',
          style: TextStyle(
            color: _T.accent,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Rota kuyruğuna eklenecek',
          style: TextStyle(color: _T.accent.withOpacity(0.7), fontSize: 12.5),
        ),
      ],
    );
  }
}

class _MapIllustration extends StatelessWidget {
  const _MapIllustration({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dış halka (pulse)
            Transform.scale(
              scale: pulse.value,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _T.accent.withOpacity(0.06),
                      _T.accent.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Orta daire — harita arka planı
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A3A5C).withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Grid çizgileri (harita hissi)
                  CustomPaint(
                    size: const Size(100, 100),
                    painter: _MapGridPainter(),
                  ),
                  // Rota çizgisi
                  CustomPaint(
                    size: const Size(100, 100),
                    painter: _RouteLinePainter(),
                  ),
                ],
              ),
            ),

            // Pin A
            Positioned(
              top: 14,
              left: 20,
              child: _MapPin(color: _T.accent, label: 'A'),
            ),
            // Pin B
            Positioned(
              bottom: 14,
              right: 20,
              child: _MapPin(color: const Color(0xFFFF6B6B), label: 'B'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
        ),
        Container(width: 2, height: 6, color: color),
        Container(
          width: 6,
          height: 3,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}

class _HintBadge extends StatelessWidget {
  const _HintBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _T.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _T.textMid),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: _T.textMid,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter — harita grid
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += size.width / 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// Custom Painter — rota çizgisi
class _RouteLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF53D6FF).withOpacity(0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.28)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.55,
        size.width * 0.65,
        size.height * 0.45,
        size.width * 0.75,
        size.height * 0.72,
      );

    canvas.drawPath(path, paint);

    // Nokta efektleri
    final dotPaint = Paint()..color = const Color(0xFF53D6FF).withOpacity(0.4);
    canvas.drawCircle(
      Offset(size.width * 0.45, size.height * 0.46),
      2.5,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.58, size.height * 0.52),
      2,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Center(
        child: Text(
          '$count',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR — akıllı filtreler + eylemler
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.hasItems,
    required this.onClear,
    required this.onCreateRoute,
    required this.droppedCount,
  });
  final bool hasItems;
  final VoidCallback onClear, onCreateRoute;
  final int droppedCount;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  int _selectedFilter = 0;
  static const _filters = [
    ('Tümü', Icons.all_inclusive_rounded),
    ('Acil', Icons.emergency_rounded),
    ('Elektif', Icons.schedule_rounded),
    ('Taburcu', Icons.logout_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _T.surface,
        border: Border(top: BorderSide(color: _T.stroke)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Hızlı filtreler ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_list_rounded,
                  size: 15,
                  color: _T.textLight,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Hızlı Filtre:',
                  style: TextStyle(
                    color: _T.textLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_filters.length, (i) {
                        final (label, icon) = _filters[i];
                        final sel = i == _selectedFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedFilter = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? _T.accent.withOpacity(0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel ? _T.accent : _T.stroke,
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 13,
                                    color: sel ? _T.accent : _T.textLight,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: sel ? _T.accent : _T.textLight,
                                      fontSize: 12,
                                      fontWeight: sel
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                // Transfer sayacı
                if (widget.droppedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A5C).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF1A3A5C).withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_hospital_rounded,
                          size: 12,
                          color: Color(0xFF1A3A5C),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.droppedCount} Transfer',
                          style: const TextStyle(
                            color: Color(0xFF1A3A5C),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Eylem butonları ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.hasItems ? widget.onClear : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Temizle'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _T.accentRed,
                      side: const BorderSide(color: _T.accentRed, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: widget.hasItems ? widget.onCreateRoute : null,
                    icon: const Icon(Icons.alt_route_rounded),
                    label: Text(
                      widget.hasItems
                          ? 'Rota Oluştur (${widget.droppedCount} Nokta)'
                          : 'Rota Oluştur',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.hasItems
                          ? const Color(0xFF1A3A5C)
                          : _T.strokeMid,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
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
// SIDEBAR — Günlük Transfer Özeti Kartı
// ─────────────────────────────────────────────────────────────────────────────
class _TransferSummaryCard extends StatelessWidget {
  const _TransferSummaryCard({
    required this.hasData,
    required this.transferCount,
    required this.totalMin,
    required this.totalKm,
  });
  final bool hasData;
  final int transferCount, totalMin;
  final double totalKm;

  String _fmt(int min) {
    if (min < 60) return '$min dk';
    return '${min ~/ 60}s ${min % 60}dk';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E3A5F), Color(0xFF0D2137)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
                    color: _T.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_hospital_rounded,
                    size: 15,
                    color: _T.accent,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Günlük Özet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: hasData
                        ? Colors.green.withOpacity(0.2)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hasData ? 'GÜNCELLENDİ' : 'BUGÜN',
                    style: TextStyle(
                      color: hasData
                          ? Colors.greenAccent
                          : Colors.white.withOpacity(0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatMini(
                    value: hasData ? '$transferCount' : '—',
                    label: 'Transfer',
                    color: _T.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatMini(
                    value: hasData ? _fmt(totalMin) : '—',
                    label: 'Süre',
                    color: const Color(0xFFFFB74D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatMini(
                    value: hasData ? '${totalKm.toStringAsFixed(1)} km' : '—',
                    label: 'Mesafe',
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatMini(
                    value: hasData ? 'Opt.' : '—',
                    label: 'Durum',
                    color: const Color(0xFFFF6B6B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  const _StatMini({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROTA SONUCU DİYALOĞU — modern hasta transfer tasarımı
// ─────────────────────────────────────────────────────────────────────────────
class _RouteResultDialog extends StatelessWidget {
  const _RouteResultDialog({
    required this.totalMin,
    required this.totalKm,
    required this.path,
    required this.hasAutoStart,
  });
  final int totalMin;
  final double totalKm;
  final List<String> path;
  final bool hasAutoStart;

  String _formatDuration(int min) {
    if (min < 60) return '$min dk';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}s' : '${h}s ${m}dk';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: _T.surface,
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
            // ── Başlık (koyu gradyan) ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _T.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _T.accent.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.alt_route_rounded,
                      color: _T.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transfer Rotası Hazır',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'OSRM — Gerçek Süre / Mesafe',
                          style: TextStyle(
                            color: Color(0xFF9DAFC8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Başarı rozeti
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: Colors.greenAccent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Optimize Edildi',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── İstatistik kartları ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _RouteStatCard(
                      icon: Icons.timer_rounded,
                      label: 'Toplam Süre',
                      value: _formatDuration(totalMin),
                      color: const Color(0xFFFFB74D),
                      bgColor: const Color(0xFFFFF8EE),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RouteStatCard(
                      icon: Icons.route_rounded,
                      label: 'Toplam Mesafe',
                      value: '${totalKm.toStringAsFixed(1)} km',
                      color: _T.accent,
                      bgColor: const Color(0xFFEEFBFF),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RouteStatCard(
                      icon: Icons.local_hospital_rounded,
                      label: 'Transfer Sayısı',
                      value: '${path.length - 1}',
                      color: const Color(0xFF66BB6A),
                      bgColor: const Color(0xFFEEF8EE),
                    ),
                  ),
                ],
              ),
            ),

            // ── Rota sırası ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Transfer Sırası',
                    style: TextStyle(
                      color: _T.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: _T.textLight,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'NN + 2-opt optimize',
                    style: TextStyle(color: _T.textLight, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                itemCount: path.length,
                itemBuilder: (_, i) {
                  final isLast = i == path.length - 1;
                  final isStart = i == 0;
                  final isEnd = isLast;

                  Color dotColor = _T.accent;
                  IconData dotIcon = Icons.circle;
                  if (isStart) {
                    dotColor = const Color(0xFF66BB6A);
                    dotIcon = Icons.flag_rounded;
                  }
                  if (isEnd && path.length > 1) {
                    dotColor = const Color(0xFF1A3A5C);
                    dotIcon = Icons.sports_score_rounded;
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sol: zaman çizelgesi
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
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(dotIcon, size: 13, color: dotColor),
                              ),
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          dotColor.withOpacity(0.3),
                                          _T.accent.withOpacity(0.15),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Sağ: adres + etiket
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isStart
                                    ? const Color(0xFFEEF8EE)
                                    : isEnd
                                    ? const Color(0xFFEEF3FF)
                                    : _T.searchBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isStart
                                      ? const Color(0xFF66BB6A).withOpacity(0.3)
                                      : isEnd
                                      ? _T.accent.withOpacity(0.2)
                                      : _T.stroke,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isStart
                                              ? 'BAŞLANGIÇ'
                                              : isEnd
                                              ? 'BİTİŞ'
                                              : 'DURAK ${i}',
                                          style: TextStyle(
                                            color: dotColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          path[i],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _T.textDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            if (hasAutoStart)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cihaz konumu alınamadı — ilk nokta başlangıç olarak alındı.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Kapat butonu ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Tamam'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A3A5C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStatCard extends StatelessWidget {
  const _RouteStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });
  final IconData icon;
  final String label, value;
  final Color color, bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
