import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../data/address_store.dart';
import '../core/models/address.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _MovePayload {
  final DateTime fromDay;
  final int fromIndex;
  final VisitPlanItem item;

  const _MovePayload({
    required this.fromDay,
    required this.fromIndex,
    required this.item,
  });
}

class _CalendarPageState extends State<CalendarPage> {
  // -------------------------
  // Limits / horizon
  // -------------------------
  static const int maxDaily = 10;
  static const int repeatHorizonDays = 730;

  // -------------------------
  // Modern UI palette (yapıyı bozmaz, sadece görünüm)
  // -------------------------
  static const Color _bg = Color(0xFF0B0C10);
  static const Color _panel = Color(0xFF121420);
  static const Color _panel2 = Color(0xFF0F111A);
  static const Color _borderStrong = Color(0x26FFFFFF); // 15%
  static const Color _borderSoft = Color(0x14FFFFFF); // 8%
  static const Color _text = Color(0xFFF5F7FF);
  static const Color _muted = Color(0xB3FFFFFF); // 70%

  BoxDecoration _glassBox({bool strong = false, double r = 18}) {
    return BoxDecoration(
      color: (strong ? _panel : _panel2).withOpacity(strong ? 0.62 : 0.46),
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: strong ? _borderStrong : _borderSoft),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.36),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _glass({
    required Widget child,
    bool strong = false,
    EdgeInsets? pad,
    double radius = 18,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: pad ?? const EdgeInsets.all(10),
          decoration: _glassBox(strong: strong, r: radius),
          child: child,
        ),
      ),
    );
  }

  TextStyle get _tTitle => const TextStyle(
        color: _text,
        fontWeight: FontWeight.w800,
        fontSize: 15,
        letterSpacing: 0.2,
      );

  TextStyle get _tBody => const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
      );

  Widget _pill(String text, {bool solid = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.92),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  // -------------------------
  // Data
  // -------------------------
  List<Address> get addresses => AddressStore.items;
  Address? selectedAddress;

  late DateTime weekStart; // monday
  late DateTime selectedDay;

  /// Gün bazında sıralı plan
  final Map<DateTime, List<VisitPlanItem>> _planByDay = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    weekStart = _startOfWeek(now);
    selectedDay = _dateOnly(now);
  }

  // -------------------------
  // Helpers
  // -------------------------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfWeek(DateTime d) {
    final only = _dateOnly(d);
    final diff = only.weekday - DateTime.monday;
    return only.subtract(Duration(days: diff));
  }

  String _newSeriesId(String title) =>
      '${DateTime.now().microsecondsSinceEpoch}-${title.hashCode}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _countForDay(DateTime dayKey) => (_planByDay[dayKey] ?? const []).length;

  List<VisitPlanItem> _listForDay(DateTime dayKey) =>
      _planByDay.putIfAbsent(dayKey, () => <VisitPlanItem>[]);

  // -------------------------
  // Series ops
  // -------------------------
  void _removeSeriesEverywhere(String seriesId) {
    final keys = _planByDay.keys.toList();
    for (final k in keys) {
      final list = _planByDay[k];
      if (list == null) continue;

      list.removeWhere((it) => it.seriesId == seriesId);

      if (list.isEmpty) {
        _planByDay.remove(k);
      } else {
        _planByDay[k] = list;
      }
    }
  }

  bool _addItemToDay(DateTime dayKey, VisitPlanItem item) {
    final list = _listForDay(dayKey);
    if (list.length >= maxDaily) return false;

    list.add(item);
    _planByDay[dayKey] = list;
    return true;
  }

  void _addWithRepeat({required DateTime baseDay, required VisitPlanItem item}) {
    final baseKey = _dateOnly(baseDay);

    if (_countForDay(baseKey) >= maxDaily) {
      _toast('Bu gün için limit dolu (max $maxDaily).');
      return;
    }

    _addItemToDay(baseKey, item);

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

      // doluysa o günü atla
      if (_countForDay(occ) < maxDaily) {
        _addItemToDay(occ, item);
      }
      i++;
    }
  }

  // -------------------------
  // Dialog (repeat + note)
  // -------------------------
  Future<VisitPlanItem?> _showAddOrEditDialog({
    required String title,
    VisitPlanItem? existing,
  }) async {
    RepeatType selected = existing?.repeat ?? RepeatType.none;
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final res = await showDialog<VisitPlanItem>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(existing == null ? 'Plan Ekle' : 'Planı Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('Tekrar', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<RepeatType>(
                value: selected,
                items: RepeatType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) => selected = v ?? RepeatType.none,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Not', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Not yaz...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final note = noteCtrl.text.trim();
                Navigator.pop(
                  context,
                  VisitPlanItem(
                    title: title,
                    repeat: selected,
                    note: note.isEmpty ? null : note,
                    seriesId: existing?.seriesId ?? _newSeriesId(title),
                  ),
                );
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    noteCtrl.dispose();
    return res;
  }

  // -------------------------
  // Actions: add / edit / move / reorder
  // -------------------------
  Future<void> _handleDropAddress(Address address, DateTime dayKey) async {
    if (_countForDay(dayKey) >= maxDaily) {
      _toast('Bu gün için limit dolu (max $maxDaily).');
      return;
    }

    final item = await _showAddOrEditDialog(title: address.address);
    if (item == null) return;

    setState(() {
      _addWithRepeat(baseDay: dayKey, item: item);
    });
  }

  Future<void> _editItem(DateTime dayKey, int index) async {
    final list = _planByDay[dayKey];
    if (list == null || index < 0 || index >= list.length) return;

    final old = list[index];
    final updated = await _showAddOrEditDialog(title: old.title, existing: old);
    if (updated == null) return;

    setState(() {
      // repeat değişince eski seri kalmasın
      _removeSeriesEverywhere(old.seriesId);
      _addWithRepeat(baseDay: dayKey, item: updated);
    });
  }

  void _moveItemToDay(_MovePayload payload, DateTime targetDay) {
    final fromKey = _dateOnly(payload.fromDay);
    final toKey = _dateOnly(targetDay);

    if (_sameDay(fromKey, toKey)) return;

    if (_countForDay(toKey) >= maxDaily) {
      _toast('Hedef gün dolu (max $maxDaily).');
      return;
    }

    final fromList = _planByDay[fromKey];
    if (fromList == null || payload.fromIndex >= fromList.length) return;

    setState(() {
      fromList.removeAt(payload.fromIndex);
      if (fromList.isEmpty) {
        _planByDay.remove(fromKey);
      } else {
        _planByDay[fromKey] = fromList;
      }

      final toList = _listForDay(toKey);
      toList.add(payload.item);
      _planByDay[toKey] = toList;
    });
  }

  void _reorderWithinDay(DateTime dayKey, int oldIndex, int newIndex) {
    final list = _planByDay[dayKey];
    if (list == null) return;

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      _planByDay[dayKey] = list;
    });
  }

  // -------------------------
  // UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    final days = List<DateTime>.generate(7, (i) => weekStart.add(Duration(days: i)));

    // seçili adres store’dan silindiyse null
    if (selectedAddress != null && !addresses.any((a) => a.code == selectedAddress!.code)) {
      selectedAddress = null;
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // ---- Top bar (aynı yapı, modern görünüm + Geri butonu)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _glass(
                strong: true,
                pad: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    // ✅ Geri butonu (takvimden çıkabilmen için)
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white.withOpacity(0.92),
                        size: 20,
                      ),
                      tooltip: 'Geri',
                    ),
                    const SizedBox(width: 2),

                    IconButton(
                      onPressed: () => setState(() => weekStart = weekStart.subtract(const Duration(days: 7))),
                      icon: Icon(Icons.chevron_left, color: Colors.white.withOpacity(0.92)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => weekStart = weekStart.add(const Duration(days: 7))),
                      icon: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.92)),
                    ),
                    const SizedBox(width: 6),

                    // dropdown container
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Address>(
                          value: selectedAddress,
                          dropdownColor: const Color(0xFF151826),
                          hint: Text('Adresler', style: TextStyle(color: Colors.white.withOpacity(0.70))),
                          iconEnabledColor: Colors.white.withOpacity(0.85),
                          items: addresses
                              .map(
                                (a) => DropdownMenuItem<Address>(
                                  value: a,
                                  child: Text(
                                    a.address,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => selectedAddress = v),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // draggable address (dropdown’dan seç, sürükle)
                    if (selectedAddress != null)
                      Draggable<Object>(
                        data: selectedAddress!,
                        feedback: Material(
                          color: Colors.transparent,
                          child: _glass(
                            strong: true,
                            pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                selectedAddress!.address,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.55,
                          child: _pill('Sürükle', solid: false),
                        ),
                        child: _pill('Sürükle', solid: true),
                      ),

                    const Spacer(),
                    Text('Takvim', style: _tTitle),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ---- Week columns
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: days.map((day) {
                    final dayKey = _dateOnly(day);
                    final list = _planByDay[dayKey] ?? <VisitPlanItem>[];
                    final isSel = _sameDay(dayKey, selectedDay);

                    return Container(
                      width: 176,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSel ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(isSel ? 0.16 : 0.10)),
                      ),
                      child: DragTarget<Object>(
                        onWillAcceptWithDetails: (_) => true,
                        onAcceptWithDetails: (details) {
                          final data = details.data;

                          if (data is Address) {
                            _handleDropAddress(data, dayKey);
                            return;
                          }
                          if (data is _MovePayload) {
                            setState(() => _moveItemToDay(data, dayKey));
                            return;
                          }
                        },
                        builder: (context, candidate, rejected) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // day header
                              InkWell(
                                onTap: () => setState(() => selectedDay = dayKey),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.02),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${day.day}/${day.month}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      _pill('${list.length}/$maxDaily', solid: false),
                                    ],
                                  ),
                                ),
                              ),

                              // body
                              Expanded(
                                child: list.isEmpty
                                    ? Center(
                                        child: Opacity(
                                          opacity: 0.8,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.inbox_outlined, color: Colors.white.withOpacity(0.55)),
                                              const SizedBox(height: 6),
                                              Text('Boş', style: _tBody),
                                            ],
                                          ),
                                        ),
                                      )
                                    : ReorderableListView.builder(
                                        padding: const EdgeInsets.all(10),
                                        itemCount: list.length,
                                        buildDefaultDragHandles: false,
                                        onReorder: (oldIndex, newIndex) =>
                                            _reorderWithinDay(dayKey, oldIndex, newIndex),
                                        itemBuilder: (context, index) {
                                          final item = list[index];

                                          return Container(
                                            key: ValueKey(
                                              '${dayKey.toIso8601String()}-$index-${item.seriesId}-${item.title}',
                                            ),
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(color: Colors.white.withOpacity(0.10)),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.22),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.98),
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 13.5,
                                                    letterSpacing: 0.15,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    // same-day reorder handle
                                                    ReorderableDragStartListener(
                                                      index: index,
                                                      child: Icon(
                                                        Icons.drag_handle,
                                                        color: Colors.white.withOpacity(0.85),
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _pill(item.repeat.short, solid: true),
                                                    const SizedBox(width: 8),
                                                    if (item.note != null && item.note!.trim().isNotEmpty)
                                                      Expanded(
                                                        child: Text(
                                                          item.note!,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: _tBody,
                                                        ),
                                                      ),
                                                    IconButton(
                                                      visualDensity: VisualDensity.compact,
                                                      onPressed: () => _editItem(dayKey, index),
                                                      icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.90), size: 18),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),

                                                // cross-day move
                                                Draggable<Object>(
                                                  data: _MovePayload(
                                                    fromDay: dayKey,
                                                    fromIndex: index,
                                                    item: item,
                                                  ),
                                                  feedback: Material(
                                                    color: Colors.transparent,
                                                    child: _glass(
                                                      strong: true,
                                                      pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                      child: ConstrainedBox(
                                                        constraints: const BoxConstraints(maxWidth: 220),
                                                        child: Text(
                                                          item.title,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.w900,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.swap_horiz, color: Colors.white.withOpacity(0.88), size: 18),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Taşı',
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.85),
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.35), size: 14),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}