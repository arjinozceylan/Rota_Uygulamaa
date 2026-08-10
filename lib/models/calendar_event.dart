enum ShiftType { morning, afternoon }

enum RepeatType { none, daily, weekly, monthly }

extension RepeatTypeLabel on RepeatType {
  String get label {
    switch (this) {
      case RepeatType.none:
        return 'Tek Seferlik';
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
        return 'Hft';
      case RepeatType.monthly:
        return 'Ay';
    }
  }
}

/// Saat yok → gün içi "ziyaret sırası" var.
/// Tekrar yönetimi için seriesId kullanıyoruz.
class VisitPlanItem {
  final String title;
  final RepeatType repeat;
  final String? note;

  /// Aynı tekrara ait tüm kopyalar aynı seriesId taşır.
  final String seriesId;

  const VisitPlanItem({
    required this.title,
    required this.seriesId,
    this.repeat = RepeatType.none,
    this.note,
  });

  VisitPlanItem copyWith({
    RepeatType? repeat,
    String? note,
    bool keepNoteWhenNull = true,
  }) {
    return VisitPlanItem(
      title: title,
      seriesId: seriesId,
      repeat: repeat ?? this.repeat,
      note: (note == null && keepNoteWhenNull) ? this.note : note,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'seriesId': seriesId,
    'repeat': repeat.name,
    'note': note,
  };

  factory VisitPlanItem.fromJson(Map<String, dynamic> json) {
    return VisitPlanItem(
      title: json['title'] as String,
      seriesId: json['seriesId'] as String,
      repeat: RepeatType.values.byName(json['repeat'] as String? ?? 'none'),
      note: json['note'] as String?,
    );
  }
}
