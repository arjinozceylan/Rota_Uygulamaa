enum RepeatType { none, daily, weekly, monthly }

extension RepeatTypeLabel on RepeatType {
  String get label {
    switch (this) {
      case RepeatType.none:
        return 'Tek Sefer';
      case RepeatType.daily:
        return 'Günlük';
      case RepeatType.weekly:
        return 'Haftalık';
      case RepeatType.monthly:
        return 'Aylık';
    }
  }

  String get short {
    switch (this) {
      case RepeatType.none:
        return 'Tek';
      case RepeatType.daily:
        return 'Gün';
      case RepeatType.weekly:
        return 'Hafta';
      case RepeatType.monthly:
        return 'Ay';
    }
  }
}

class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final RepeatType repeat;

  final String? note;

  CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    this.repeat = RepeatType.none,
    this.note,
  });
}
