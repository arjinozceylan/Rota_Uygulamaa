import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final MapController _mapController = MapController();

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<_SearchHit> _hits = [];

  // default: İzmir merkez
  LatLng _center = const LatLng(38.4237, 27.1428);

  LatLng? _picked;
  String? _pickedLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Haritadan Seç')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 12,
              onTap: (tapPos, latlng) {
                setState(() {
                  _picked = latlng;
                  _pickedLabel = null;
                });
                // Try to resolve a human-readable address for the picked point.
                _reverseGeocode(latlng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rota_uygulamaa',
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.location_pin, size: 44),
                    ),
                  ],
                ),
            ],
          ),

          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Yer ara (örn: İzmir Balçova)',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (_searchCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchCtrl.clear();
                                          _hits = [];
                                        });
                                      },
                                    )),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (txt) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          () async {
                            await _doSearch(txt);
                          },
                        );
                      },
                    ),

                    if (_hits.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _hits.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final h = _hits[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                h.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                setState(() {
                                  _center = h.point;
                                  _picked = h.point;
                                  _pickedLabel = h.label;
                                  _hits = [];
                                });
                                _mapController.move(h.point, 15);
                                FocusScope.of(context).unfocus();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _picked == null
                ? null
                : () {
                    final p = _picked!;
                    Navigator.pop(
                      context,
                      MapPickResult(
                        point: p,
                        label:
                            _pickedLabel ??
                            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                      ),
                    );
                  },
            child: Text(
              _picked == null
                  ? 'Haritadan bir nokta seç'
                  : (_pickedLabel == null
                        ? 'Seç (${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)})'
                        : 'Seç: ${_pickedLabel!}'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _doSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _hits = []);
      return;
    }

    setState(() => _loading = true);

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '8',
        'countrycodes': 'tr',
        'accept-language': 'tr',
      });

      final res = await http.get(
        uri,
        headers: {
          // Nominatim usage policy expects a valid User-Agent identifying your app.
          'User-Agent': 'Rota_Uygulamaa/1.0 (local-dev)',
          'Accept-Language': 'tr',
        },
      );

      if (res.statusCode != 200) {
        if (mounted) setState(() => _hits = []);
        return;
      }

      final data = jsonDecode(res.body);
      if (data is! List) {
        if (mounted) setState(() => _hits = []);
        return;
      }

      final results = <_SearchHit>[];
      for (final item in data) {
        if (item is! Map) continue;
        final label = (item['display_name'] ?? '').toString();
        final latStr = (item['lat'] ?? '').toString();
        final lonStr = (item['lon'] ?? '').toString();
        final lat = double.tryParse(latStr);
        final lon = double.tryParse(lonStr);
        if (label.isEmpty || lat == null || lon == null) continue;
        results.add(_SearchHit(label, LatLng(lat, lon)));
      }

      if (mounted) setState(() => _hits = results);
    } catch (_) {
      if (mounted) setState(() => _hits = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reverseGeocode(LatLng p) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': p.latitude.toString(),
        'lon': p.longitude.toString(),
        'format': 'jsonv2',
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'tr',
      });

      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'Rota_Uygulamaa/1.0 (local-dev)',
          'Accept-Language': 'tr',
        },
      );

      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      if (data is! Map) return;
      final label = (data['display_name'] ?? '').toString();
      if (label.isEmpty) return;

      if (!mounted) return;
      // Only set the label if the picked point hasn't changed.
      if (_picked != null &&
          (_picked!.latitude == p.latitude) &&
          (_picked!.longitude == p.longitude)) {
        setState(() => _pickedLabel = label);
      }
    } catch (_) {
      // Ignore network/parse errors
    }
  }
}

class _SearchHit {
  final String label;
  final LatLng point;
  const _SearchHit(this.label, this.point);
}

class MapPickResult {
  final LatLng point;
  final String label;
  const MapPickResult({required this.point, required this.label});
}
