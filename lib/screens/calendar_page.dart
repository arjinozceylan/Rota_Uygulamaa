import 'package:flutter/material.dart';
import '../models/calendar_event.dart';
import '../data/address_store.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // Üst dropdown
  final List<String> addresses = AddressStore.items;
  String selectedAddress = 'Adresler';

  late DateTime weekStart; // Pazartesi
  late DateTime selectedDay;

  // Saat aralığı: 08:00–17:00 (10 satır)
  final List<int> hours = List<int>.generate(10, (i) => 8 + i);

  // Eventler (gün bazında)
  final Map<DateTime, List<CalendarEvent>> _eventsByDay = {};

  // Tekrarları ileri tarihlere kopyalama sınırı
  static const int _repeatHorizonDays = 730; // ~2 yıl

  void _addEventToDay(DateTime dayKey, CalendarEvent ev) {
    _eventsByDay.putIfAbsent(dayKey, () => []);
    _eventsByDay[dayKey]!.add(ev);
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  DateTime _addMonthsKeepingDay(DateTime dt, int addMonths) {
    final int totalMonths = (dt.year * 12) + (dt.month - 1) + addMonths;
    final int y = totalMonths ~/ 12;
    final int m = (totalMonths % 12) + 1;
    final int day = dt.day.clamp(1, _daysInMonth(y, m));
    return DateTime(y, m, day, dt.hour, dt.minute);
  }

  // =========================
  // ✅ ÇAKIŞMA KONTROLÜ
  // =========================
  bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    // [aStart, aEnd) ile [bStart, bEnd) kesişiyor mu?
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  bool _hasConflictOnDay(DateTime dayKey, DateTime start, DateTime end) {
    final list = _eventsByDay[dayKey];
    if (list == null || list.isEmpty) return false;

    for (final e in list) {
      if (_overlaps(start, end, e.start, e.end)) return true;
    }
    return false;
  }

  /// Tekrarları da dahil ederek eklemeyi dener.
  /// Çakışma varsa: (false, conflictDate)
  /// Başarılıysa: (true, null)
  ({bool ok, DateTime? conflictDay}) _tryAddEventWithRepeat(CalendarEvent base) {
    final occurrences = <({DateTime start, DateTime end})>[];

    // base occurrence
    occurrences.add((start: base.start, end: base.end));

    if (base.repeat != RepeatType.none) {
      final baseStartOnly = _dateOnly(base.start);
      final horizon = baseStartOnly.add(const Duration(days: _repeatHorizonDays));

      int i = 1;
      while (true) {
        DateTime occStart;
        switch (base.repeat) {
          case RepeatType.daily:
            occStart = base.start.add(Duration(days: i));
            break;
          case RepeatType.weekly:
            occStart = base.start.add(Duration(days: 7 * i));
            break;
          case RepeatType.monthly:
            occStart = _addMonthsKeepingDay(base.start, i);
            break;
          case RepeatType.none:
            occStart = base.start;
            break;
        }

        if (occStart.isAfter(horizon)) break;

        final duration = base.end.difference(base.start);
        final occEnd = occStart.add(duration);
        occurrences.add((start: occStart, end: occEnd));

        i++;
      }
    }

    // 1) Önce hepsi için çakışma kontrolü
    for (final occ in occurrences) {
      final dayKey = _dateOnly(occ.start);
      if (_hasConflictOnDay(dayKey, occ.start, occ.end)) {
        return (ok: false, conflictDay: dayKey);
      }
    }

    // 2) Çakışma yoksa ekle
    for (final occ in occurrences) {
      final dayKey = _dateOnly(occ.start);
      _addEventToDay(
        dayKey,
        CalendarEvent(
          title: base.title,
          start: occ.start,
          end: occ.end,
          repeat: base.repeat,
          note: base.note,
        ),
      );
    }

    return (ok: true, conflictDay: null);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    weekStart = _startOfWeek(now);
    selectedDay = _dateOnly(now);
  }

  @override
  Widget build(BuildContext context) {
    final days = List<DateTime>.generate(7, (i) => weekStart.add(Duration(days: i)));

    if (!addresses.contains(selectedAddress)) {
      selectedAddress = 'Adresler';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F3),
      body: SafeArea(
        child: Column(
          children: [
            // ===== ÜST YEŞİL BAR =====
            Container(
              height: 56,
              color: const Color(0xFF43A047),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 6),

                  // Dropdown
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedAddress,
                        items: addresses
                            .map((a) => DropdownMenuItem<String>(
                                  value: a,
                                  child: Text(a),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => selectedAddress = v ?? 'Adresler'),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // DRAGGABLE CHIP (adres seçilince çıkıyor)
                  if (selectedAddress != 'Adresler')
                    Draggable<String>(
                      data: selectedAddress,
                      feedback: Material(
                        color: Colors.transparent,
                        child: _dragChip(selectedAddress, active: true),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.55,
                        child: _dragChip(selectedAddress),
                      ),
                      child: _dragChip(selectedAddress),
                    ),

                  const Spacer(),
                  const Text(
                    'Takvim',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),

            // ===== KALAN ALAN =====
            Expanded(
              child: Container(
                color: const Color(0xFFF3F4F3),
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      children: [
                        // Ay başlığı + oklar
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_monthName(days[0].month)} ${days[0].year}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(width: 10),
                                _navBtn(
                                  Icons.chevron_left,
                                  () => setState(() {
                                    weekStart = weekStart.subtract(const Duration(days: 7));
                                    selectedDay = _dateOnly(weekStart);
                                  }),
                                ),
                                const SizedBox(width: 6),
                                _navBtn(
                                  Icons.chevron_right,
                                  () => setState(() {
                                    weekStart = weekStart.add(const Duration(days: 7));
                                    selectedDay = _dateOnly(weekStart);
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Siyah grid alanı
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: const Color(0xFF111111),
                              child: Column(
                                children: [
                                  // Gün başlıkları
                                  Container(
                                    height: 44,
                                    padding: const EdgeInsets.only(left: 64),
                                    color: const Color(0xFF1E1E1E),
                                    child: Row(
                                      children: days.map((d) {
                                        final isSel = _isSameDate(d, selectedDay);
                                        return Expanded(
                                          child: InkWell(
                                            onTap: () => setState(() => selectedDay = _dateOnly(d)),
                                            child: Container(
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                                                color: isSel ? Colors.white.withOpacity(0.07) : Colors.transparent,
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    _weekdayShort(d.weekday),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${d.day}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),

                                  // Saat satırları
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: hours.length,
                                      itemBuilder: (context, rowIdx) {
                                        final hour = hours[rowIdx];
                                        return SizedBox(
                                          height: 56,
                                          child: Row(
                                            children: [
                                              // Saat etiketi
                                              Container(
                                                width: 64,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                                ),
                                                child: Text(
                                                  '${hour.toString().padLeft(2, '0')}:00',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),

                                              // 7 gün hücre
                                              ...days.map((day) {
                                                final slotStart =
                                                    DateTime(day.year, day.month, day.day, hour, 0);
                                                final eventAtSlot = _findEventAtSlot(day, hour);

                                                return Expanded(
                                                  child: DragTarget<String>(
                                                    onWillAcceptWithDetails: (_) => true,
                                                    onAcceptWithDetails: (details) {
                                                      _handleDrop(details.data, slotStart);
                                                    },
                                                    builder: (context, candidate, rejected) {
                                                      final hovering = candidate.isNotEmpty;

                                                      return Container(
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: Colors.white.withOpacity(0.08),
                                                          ),
                                                          color: hovering
                                                              ? Colors.white.withOpacity(0.06)
                                                              : Colors.transparent,
                                                        ),
                                                        child: eventAtSlot == null
                                                            ? null
                                                            : Align(
                                                                alignment: Alignment.centerLeft,
                                                                child: Padding(
                                                                  padding: const EdgeInsets.symmetric(
                                                                      horizontal: 6, vertical: 4),
                                                                  child: GestureDetector(
                                                                    onTap: () => _showEventDetail(day, eventAtSlot),
                                                                    onSecondaryTapDown: (_) =>
                                                                        _removeEvent(day, eventAtSlot),
                                                                    child: Container(
                                                                      padding: const EdgeInsets.symmetric(
                                                                          horizontal: 8, vertical: 5),
                                                                      decoration: BoxDecoration(
                                                                        color: Colors.white.withOpacity(0.12),
                                                                        borderRadius: BorderRadius.circular(999),
                                                                        border: Border.all(
                                                                            color: Colors.white.withOpacity(0.16)),
                                                                      ),
                                                                      child: Text(
                                                                        '${_hhmm(eventAtSlot.start)}-${_hhmm(eventAtSlot.end)} • ${eventAtSlot.title}',
                                                                        style: const TextStyle(
                                                                          color: Colors.white,
                                                                          fontSize: 11,
                                                                          fontWeight: FontWeight.w700,
                                                                        ),
                                                                        overflow: TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                      );
                                                    },
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectedAddress == 'Adresler'
                                ? 'İpucu: Dropdown’dan istediğin adresi seç.'
                                : 'İpucu: Chip’i istediğin gün+saat hücresine bırak. (Sağ tık: sil)',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.45),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  // ====== DROP: bitiş + tekrar + not ======
  Future<void> _handleDrop(String address, DateTime slotStart) async {
    if (address.trim().isEmpty || address == 'Adresler') return;

    final dayKey = _dateOnly(slotStart);
    setState(() => selectedDay = dayKey);

    TimeOfDay endTime = TimeOfDay(hour: slotStart.hour + 1, minute: 0);
    RepeatType repeat = RepeatType.none;
    final noteCtrl = TextEditingController();

    final created = await showModalBottomSheet<CalendarEvent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        DateTime toDateTime(TimeOfDay t) => DateTime(
              slotStart.year,
              slotStart.month,
              slotStart.day,
              t.hour,
              t.minute,
            );

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(address, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Başlangıç: ${slotStart.hour.toString().padLeft(2, '0')}:00',
                    style: TextStyle(color: Colors.black.withOpacity(0.65)),
                  ),
                  const SizedBox(height: 12),

                  const Text('Bitiş', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _timeField(
                    label: 'Bitiş Saati',
                    value: endTime.format(ctx),
                    onTap: () async {
                      final t = await showTimePicker(context: ctx, initialTime: endTime);
                      if (t == null) return;
                      setModal(() => endTime = t);
                    },
                  ),

                  const SizedBox(height: 14),
                  const Text('Tekrar', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<RepeatType>(
                        value: repeat,
                        isExpanded: true,
                        items: RepeatType.values
                            .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                            .toList(),
                        onChanged: (v) => setModal(() => repeat = v ?? RepeatType.none),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Text('Not', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Örn: Kapı kodu / Hasta onayı / vs',
                      filled: true,
                      fillColor: const Color(0xFFF6F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final s = slotStart;
                            final e = toDateTime(endTime);

                            if (!e.isAfter(s)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bitiş saati başlangıçtan sonra olmalı')),
                              );
                              return;
                            }

                            // ✅ Aynı gün içinde anlık çakışma kontrolü (modal kapanmadan)
                            if (_hasConflictOnDay(_dateOnly(s), s, e)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Bu saat aralığında başka bir adres var (çakışma).')),
                              );
                              return;
                            }

                            Navigator.pop(
                              ctx,
                              CalendarEvent(
                                title: address,
                                start: s,
                                end: e,
                                repeat: repeat,
                                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                              ),
                            );
                          },
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (created == null) return;

    setState(() {
      final result = _tryAddEventWithRepeat(created);
      if (!result.ok) {
        final d = result.conflictDay!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Çakışma var: ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
            ),
          ),
        );
      }
    });
  }

  // ====== Event bul / sil / detay ======
  CalendarEvent? _findEventAtSlot(DateTime day, int hour) {
    final list = _eventsByDay[_dateOnly(day)];
    if (list == null) return null;

    for (final e in list) {
      if (_isSameDate(e.start, day) && e.start.hour == hour) return e;
    }
    return null;
  }

  void _removeEvent(DateTime day, CalendarEvent ev) {
    final key = _dateOnly(day);
    setState(() {
      final list = _eventsByDay[key];
      if (list == null) return;
      list.remove(ev);
      if (list.isEmpty) _eventsByDay.remove(key);
    });
  }

  void _showEventDetail(DateTime day, CalendarEvent ev) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ev.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tarih: ${day.day}.${day.month}.${day.year}'),
            const SizedBox(height: 6),
            Text('Saat: ${_hhmm(ev.start)} - ${_hhmm(ev.end)}'),
            const SizedBox(height: 6),
            Text('Tekrar: ${ev.repeat.label}'),
            if (ev.note != null && ev.note!.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Not:', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(ev.note!),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeEvent(day, ev);
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // ====== küçük UI parçaları ======
  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  static Widget _dragChip(String text, {bool active = false}) {
    return Container(
      height: 32,
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, size: 16, color: Color(0xFF2E7D32)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            const Icon(Icons.access_time, size: 18),
          ],
        ),
      ),
    );
  }

  // ====== Date helpers ======
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfWeek(DateTime d) {
    final only = _dateOnly(d);
    final diff = only.weekday - DateTime.monday;
    return only.subtract(Duration(days: diff));
  }

  String _weekdayShort(int w) {
    switch (w) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return '';
    }
  }

  String _monthName(int m) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[m - 1];
  }

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}