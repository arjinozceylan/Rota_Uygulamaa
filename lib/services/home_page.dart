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
import '../screens/calendar_page.dart';
import '../screens/map_picker_page.dart';
import 'osrm_route_service.dart';

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
  int _mapPickCodeCounter = 1;
  final OsrmRouteService _osrm = const OsrmRouteService();

  Address _makeMapPickedAddress(MapPickResult res) {
    final code = 'P${(_mapPickCodeCounter++).toString().padLeft(3, '0')}';

    final lat = res.point.latitude;
    final lng = res.point.longitude;

    return Address(
      code: code,
      address: res.label,
      placeId: 'osm:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
      lat: lat,
      lng: lng,
    );
  }

  Future<void> _openMapPicker() async {
    final res = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerPage()),
    );
    if (!mounted || res == null) return;

    // Haritadan seçilen adresi havuza/kartlara ekle
    _addAddressToPoolAndCards(_makeMapPickedAddress(res));

    // UI temizliği
    setState(() {
      suggestions = <Address>[];
      searchCtrl.clear();
    });
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
        suggestions = <Address>[];
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
          suggestions = <Address>[];
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

  Future<void> _runDemoRoute() async {
    if (dropped.isEmpty) return;

    // Build a map from address text to Address object (with lat/lng)
    final Map<String, Address> byText = {
      for (final a in AddressStore.items) a.address: a,
    };

    // Collect stops (must have coordinates)
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

    // Decide start:
    // - If user selected a start address, use it.
    // - If START (null) is selected, we cannot read device location on desktop yet;
    //   so we pick the first stop as the temporary start.
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

    // Build node order: start + remaining stops (no duplicates)
    final nodes = <Address>[start];
    for (final s in stops) {
      if (s.address == start.address) continue;
      nodes.add(s);
    }

    // Show loading dialog
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
      // Fetch NxN matrix
      final matrix = await _osrm.table(
        coords: nodes
            .map((a) => LatLng(a.lat!, a.lng!))
            .toList(growable: false),
      );

      // Build route using NN + 2-opt over matrix durations
      final idxRoute = _nearestNeighborTourIdx(matrix, 0);
      final improved = _twoOptIdx(matrix, idxRoute);

      final totalMin = _tourCostIdxMin(matrix, improved).round();
      final totalKm = _tourCostIdxKm(matrix, improved);

      // Build pretty path labels (return to start)
      final path = improved.map((i) => nodes[i].address).toList();

      if (!mounted) return;
      Navigator.pop(context); // close loading

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Rota (Gerçek Süre/Mesafe - OSRM)'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Toplam süre: $totalMin dk'),
                  const SizedBox(height: 6),
                  Text('Toplam mesafe: ${totalKm.toStringAsFixed(1)} km'),
                  const SizedBox(height: 12),
                  Text(path.join(' → ')),
                  if (selectedStartAddress == null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Not: START (cihaz konumu) şu an masaüstünde okunmuyor. Geçici olarak ilk adres başlangıç alındı.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OSRM hata: $e')));
    }
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
                              suggestions = <Address>[];
                              searchCtrl.clear();
                            });

                            // Haritadan Seç moduna geçildiyse harita sayfasını aç
                            if (mode == AddressInputMode.maps) {
                              _openMapPicker();
                            }
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
                              onPressed: dropped.isEmpty
                                  ? null
                                  : () => _runDemoRoute(),
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
///  GERÇEK ROTA (OSRM Matrix)
///  Nearest Neighbor + 2-opt
///  (Index bazlı)
/// ===============================

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

// Toplam süre (dakika)
double _tourCostIdxMin(OsrmMatrix m, List<int> path) {
  double sum = 0;
  for (int k = 0; k < path.length - 1; k++) {
    sum += _durMin(m, path[k], path[k + 1]);
  }
  return sum;
}

// Toplam mesafe (km)
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

  route.add(startIdx); // return
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
