import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

import '../data/address_store.dart';
import '../models/calendar_event.dart';
import '../core/models/address.dart';
import '../screens/osm_places_service.dart';
import '../widgets/center_drop_card.dart';
import '../widgets/top_action_bar.dart';
import 'calendar_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int maxDaily = 20;

  // Üstte görünen draggable kartlar
  final List<String> addressCards = [];

  // Dropdown havuzu (dinamik)
  final List<String> filterItems = ['Adresler'];
  String selectedFilter = 'Adresler';

  // Günlük plan (drop alanı)
  final List<String> dropped = [];
  final Map<String, RepeatType> repeatByAddress = {};

  String syncStatus = ' ';

  // Search (CenterDropCard için)
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController manualAddressCtrl = TextEditingController();
  bool isSearching = false;
  List<Address> suggestions = [];
  final OsmPlacesService _placesService = const OsmPlacesService();
  Timer? _searchDebounce;
  int _latestSearchId = 0;
  AddressInputMode inputMode = AddressInputMode.maps;
  int _manualCodeCounter = 1;

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

  // ✅ Yeni: başlangıç adresi seçimi (null => START / cihaz konumu)
  String? selectedStartAddress;

  @override
  void initState() {
    super.initState();

    // Store’daki adresleri dropdown’a çek
    for (final a in AddressStore.items) {
      final text = a.address;
      if (!filterItems.contains(text)) filterItems.add(text);
    }

    searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchCtrl.dispose();
    manualAddressCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = searchCtrl.text.trim();
    _searchDebounce?.cancel();

    if (q.isEmpty) {
      setState(() {
        suggestions = [];
        isSearching = false;
      });
      return;
    }

    setState(() => isSearching = true);

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final searchId = ++_latestSearchId;
      final query = searchCtrl.text.trim();
      if (query.isEmpty) {
        if (!mounted) return;
        setState(() {
          suggestions = [];
          isSearching = false;
        });
        return;
      }

      final remoteResults = await _placesService.search(query: query);

      if (!mounted || searchId != _latestSearchId) return;

      setState(() {
        suggestions = remoteResults; // ✅ List<Address>
        isSearching = false;
      });
    });
  }

  void _addManualAddress() {
    final address = manualAddressCtrl.text.trim();
    if (address.isEmpty) return;
    _addAddressToPoolAndCards(_makeManualAddress(address));
    setState(() {
      manualAddressCtrl.clear();
    });
  }

  // Tek yerden ekleme: store + dropdown + kartlar
  void _addAddressToPoolAndCards(Address addressObj) {
    final a = addressObj.address.trim();
    if (a.isEmpty) return;

    setState(() {
      AddressStore.add(addressObj);

      if (!filterItems.contains(a)) {
        filterItems.add(a);
      }

      if (!addressCards.contains(a)) {
        addressCards.insert(0, a);
      }

      if (!filterItems.contains(selectedFilter)) {
        selectedFilter = 'Adresler';
      }

      syncStatus = ' ';
    });
  }

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

        // Başlangıç daha önce seçildiyse ama listeden silindiyse reset (safety)
        if (selectedStartAddress != null &&
            !dropped.contains(selectedStartAddress)) {
          selectedStartAddress = null;
        }
      });
    }
  }

  void _showAppInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SizedBox(height: 8),
                    Text(
                      'Uygulama Bilgisi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    _InfoSection(
                      title: 'Genel',
                      body:
                          'Uygulama, masaüstü + mobil olmak üzere iki parçadan oluşan bir rota planlama ve navigasyon sistemidir.',
                    ),
                    _InfoSection(
                      title: 'Adres Havuzu',
                      body:
                          'Adresler veritabanında tutulur ve gerektiğinde Excel ile toplu içeri alınabilir. Toplam adres sayısı 5000+ olabilir; ancak günlük rota pratikte ~20 adres ile sınırlıdır.',
                    ),
                    _InfoSection(
                      title: 'Optimizasyon Hedefi',
                      body:
                          '“En kısa rota” toplam süre minimizasyonudur (mesafe değil). Başlangıç/bitiş kullanıcıdan sabit alınmaz: mobilde cihaz konumu başlangıç kabul edilir ve rota başlangıca geri döner.',
                    ),
                    _InfoSection(
                      title: 'Masaüstü vs Mobil',
                      body:
                          'Masaüstü planlar (takvim + havuz) → mobil navigasyon yapar (uygulama içi). Aynı hesapla senkron çalışır.',
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ CSV import (Google Sheets / LibreOffice / Not Defteri)
  // UI'ye dokunmadan upload butonunu çalıştırır.
  Future<void> _importAddressesFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;

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

      // Ayırıcı: bazı TR exportlarda ';' olur, bazılarında ',' olur.
      final header = lines.first;
      final commaCount = ','.allMatches(header).length;
      final semiCount = ';'.allMatches(header).length;
      final sep = semiCount > commaCount ? ';' : ',';

      int added = 0;

      for (final line in lines) {
        final raw = line.trim();
        if (raw.isEmpty) continue;

        // ilk sütun adres
        final firstCol = raw.split(sep).first.trim();

        // başlık satırı
        if (firstCol.isEmpty) continue;
        if (firstCol.toLowerCase() == 'adres') continue;

        _addAddressToPoolAndCards(_makeManualAddress(firstCol));
        added++;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $added adres CSV’den yüklendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV yükleme hatası: $e')));
    }
  }

  void _runDemoRoute() {
    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final result = buildBestRouteDemo(
              dropped,
              startAddress: selectedStartAddress,
            );

            return AlertDialog(
              title: const Text('Örnek Rota (Süre Minimizasyonu)'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Başlangıç Adresi',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F7F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: selectedStartAddress,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('START (Cihaz konumu)'),
                            ),
                            ...dropped.map(
                              (a) => DropdownMenuItem<String?>(
                                value: a,
                                child: Text(a, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setLocal(() => selectedStartAddress = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Toplam süre: ${result.totalMinutes} dk'),
                    const SizedBox(height: 10),
                    Text(result.prettyPath),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!filterItems.contains(selectedFilter)) {
      selectedFilter = 'Adresler';
    }

    // Başlangıç adresi seçilmiş ama artık dropped içinde değilse reset (safety)
    if (selectedStartAddress != null &&
        !dropped.contains(selectedStartAddress)) {
      selectedStartAddress = null;
    }

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAF6EC), Color(0xFFDDEEE0)],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: TopActionBar(
                  filterValue: selectedFilter,
                  filterItems: filterItems,
                  onFilterChanged: (v) {
                    setState(() => selectedFilter = v);
                    if (v != 'Adresler') {
                      _addAddressToPoolAndCards(_makeManualAddress(v));
                    }
                  },
                  primaryColor: cs.primary,
                  selectedCount: dropped.length,
                  maxCount: maxDaily,
                  syncStatus: syncStatus,
                  onInfoPressed: () => _showAppInfo(context),
                  onUploadPressed: _importAddressesFromExcel,
                  onCalendarPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CalendarPage()),
                    ).then((_) {
                      setState(() {
                        for (final a in AddressStore.items) {
                          final text = a.address;
                          if (!filterItems.contains(text))
                            filterItems.add(text);
                        }
                      });
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: addressCards.map((a) {
                    return Draggable<String>(
                      data: a,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _AddressChip(text: a, ghost: true),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _AddressChip(text: a),
                      ),
                      child: _AddressChip(
                        text: a,
                        onRemove: () {
                          setState(() {
                            addressCards.remove(a);
                            AddressStore.removeByAddress(a);
                            filterItems.remove(a);

                            if (selectedStartAddress == a) {
                              selectedStartAddress = null;
                            }

                            if (!filterItems.contains(selectedFilter)) {
                              selectedFilter = 'Adresler';
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: CenterDropCard(
                          droppedAddresses: dropped,
                          onDropAddress: _dropAddress,
                          maxCount: maxDaily,
                          repeatByAddress: repeatByAddress,
                          searchController: searchCtrl,
                          manualAddressController: manualAddressCtrl,
                          inputMode: inputMode,
                          onInputModeChanged: (mode) {
                            setState(() {
                              inputMode = mode;
                              suggestions = [];
                              searchCtrl.clear();
                            });
                          },
                          onManualAddressAdd: _addManualAddress,
                          suggestions: suggestions
                              .map((a) => a.address)
                              .toList(),
                          isSearching: isSearching,
                          onSuggestionTap: (s) {
                            final match = suggestions
                                .where((a) => a.address == s)
                                .toList();

                            if (match.isNotEmpty) {
                              _addAddressToPoolAndCards(
                                match.first,
                              ); // ✅ lat/lng kaybolmaz
                            } else {
                              _addAddressToPoolAndCards(_makeManualAddress(s));
                            }

                            setState(() {
                              searchCtrl.clear();
                              suggestions =
                                  <Address>[]; // ✅ artık List<Address>
                            });
                          },
                          helperText:
                              'Kartları buraya sürükle. (Hedef: süre minimizasyonu)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: dropped.isEmpty
                                  ? null
                                  : () => setState(() {
                                      dropped.clear();
                                      repeatByAddress.clear();
                                      selectedStartAddress = null;
                                    }),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Temizle'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: dropped.isEmpty ? null : _runDemoRoute,
                              icon: const Icon(Icons.route),
                              label: const Text('Rota Oluştur'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({required this.text, this.onRemove, this.ghost = false});

  final String text;
  final VoidCallback? onRemove;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(ghost ? 0.9 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 6),
            color: Colors.black12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Sil',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: Colors.black87, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// ===============================
///  DEMO ROTA ALGORİTMASI
///  Nearest Neighbor + 2-opt
///  Başlangıç adresi seçilebilir
/// ===============================

class RouteResult {
  RouteResult({required this.path, required this.totalMinutes});
  final List<String> path;
  final int totalMinutes;

  String get prettyPath => path.join(' → ');
}

// Aynı adres çiftine stabil “süre” üret (demo)
int _stableMinutes(String a, String b) {
  int hash = 0;
  final s = '$a|$b';
  for (int i = 0; i < s.length; i++) {
    hash = (hash * 31 + s.codeUnitAt(i)) & 0x7fffffff;
  }
  // 6–38 dk arası
  return 6 + (hash % 33);
}

int _time(String a, String b) {
  if (a == b) return 0;
  return _stableMinutes(a, b);
}

int _tourCost(List<String> path) {
  int sum = 0;
  for (int i = 0; i < path.length - 1; i++) {
    sum += _time(path[i], path[i + 1]);
  }
  return sum;
}

// ✅ Başlangıç parametreli nearest neighbor turu
List<String> _nearestNeighborTour(List<String> stops, String start) {
  final unvisited = stops.toSet();

  // start stops içinde yoksa ekle
  if (!unvisited.contains(start)) {
    unvisited.add(start);
  }

  unvisited.remove(start);

  final route = <String>[start];

  String current = start;
  while (unvisited.isNotEmpty) {
    String? best;
    int bestCost = 1 << 30;

    for (final cand in unvisited) {
      final c = _time(current, cand);
      if (c < bestCost) {
        bestCost = c;
        best = cand;
      }
    }

    route.add(best!);
    unvisited.remove(best);
    current = best;
  }

  route.add(start); // geri dön
  return route;
}

List<String> _twoOpt(List<String> path) {
  if (path.length <= 4) return path;

  bool improved = true;
  List<String> best = List<String>.from(path);
  int bestCost = _tourCost(best);

  while (improved) {
    improved = false;

    for (int i = 1; i < best.length - 2; i++) {
      for (int k = i + 1; k < best.length - 1; k++) {
        final candidate = <String>[
          ...best.sublist(0, i),
          ...best.sublist(i, k + 1).reversed,
          ...best.sublist(k + 1),
        ];

        final candCost = _tourCost(candidate);
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

RouteResult buildBestRouteDemo(List<String> dropped, {String? startAddress}) {
  final stops = dropped
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  final String start = (startAddress != null && stops.contains(startAddress))
      ? startAddress
      : 'START';

  final List<String> nodes = (start == 'START') ? ['START', ...stops] : stops;

  final nn = _nearestNeighborTour(nodes, start);
  final improved = _twoOpt(nn);

  return RouteResult(path: improved, totalMinutes: _tourCost(improved));
}
