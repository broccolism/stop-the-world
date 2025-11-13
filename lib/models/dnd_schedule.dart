class DndTimeRange {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  DndTimeRange({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  // 시작 시간을 분 단위로 변환 (0~1439)
  int get startMinutes => startHour * 60 + startMinute;

  // 종료 시간을 분 단위로 변환 (0~1439)
  int get endMinutes => endHour * 60 + endMinute;

  String get displayText {
    final startHourStr = startHour.toString().padLeft(2, '0');
    final startMinuteStr = startMinute.toString().padLeft(2, '0');
    final endHourStr = endHour.toString().padLeft(2, '0');
    final endMinuteStr = endMinute.toString().padLeft(2, '0');
    return '$startHourStr:$startMinuteStr-$endHourStr:$endMinuteStr';
  }

  Map<String, dynamic> toJson() {
    return {
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
    };
  }

  factory DndTimeRange.fromJson(Map<String, dynamic> json) {
    return DndTimeRange(
      startHour: json['startHour'] as int,
      startMinute: json['startMinute'] as int,
      endHour: json['endHour'] as int,
      endMinute: json['endMinute'] as int,
    );
  }
}

class DndSchedule {
  final DateTime date;
  final List<DndTimeRange> timeRanges;

  DndSchedule({
    required this.date,
    required this.timeRanges,
  });

  // 날짜만 비교 (시간 제외)
  bool isToday() {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  // 현재 시간이 DND 시간대에 포함되는지 확인
  bool isInDndPeriod() {
    if (!isToday()) return false;

    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (final range in timeRanges) {
      if (currentMinutes >= range.startMinutes &&
          currentMinutes < range.endMinutes) {
        return true;
      }
    }

    return false;
  }

  // 48개 슬롯 (30분 단위) 배열을 시간 범위로 변환
  static List<DndTimeRange> slotsToTimeRanges(List<bool> slots) {
    final List<DndTimeRange> ranges = [];
    int? rangeStart;

    for (int i = 0; i < slots.length; i++) {
      if (slots[i]) {
        // 선택된 슬롯
        rangeStart ??= i;
      } else {
        // 선택되지 않은 슬롯
        if (rangeStart != null) {
          // 이전까지 연속된 범위가 있었음 - 범위 종료
          ranges.add(_createTimeRange(rangeStart, i));
          rangeStart = null;
        }
      }
    }

    // 마지막까지 선택된 경우
    if (rangeStart != null) {
      ranges.add(_createTimeRange(rangeStart, slots.length));
    }

    return ranges;
  }

  // 시간 범위를 48개 슬롯 배열로 변환
  static List<bool> timeRangesToSlots(List<DndTimeRange> ranges) {
    final slots = List<bool>.filled(48, false);

    for (final range in ranges) {
      final startSlot = (range.startMinutes / 30).floor();
      final endSlot = (range.endMinutes / 30).ceil();

      for (int i = startSlot; i < endSlot && i < 48; i++) {
        slots[i] = true;
      }
    }

    return slots;
  }

  static DndTimeRange _createTimeRange(int startSlot, int endSlot) {
    final startMinutes = startSlot * 30;
    final endMinutes = endSlot * 30;

    return DndTimeRange(
      startHour: startMinutes ~/ 60,
      startMinute: startMinutes % 60,
      endHour: endMinutes ~/ 60,
      endMinute: endMinutes % 60,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'timeRanges': timeRanges.map((r) => r.toJson()).toList(),
    };
  }

  factory DndSchedule.fromJson(Map<String, dynamic> json) {
    return DndSchedule(
      date: DateTime.parse(json['date'] as String),
      timeRanges: (json['timeRanges'] as List)
          .map((r) => DndTimeRange.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

