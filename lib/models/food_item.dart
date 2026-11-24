class FoodItem {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String zone; // 'fridge' | 'freezer' | 'room'
  final String registeredDate; // YYYY-MM-DD
  final String expiryDate; // YYYY-MM-DD
  final String sourceType; // 'fresh' | 'ocr' | 'receipt' | 'manual'
  final String tip;
  final bool reminderEnabled;
  final int reminderOffset; // default 3 for fridge/room, 7 for freezer
  final int estimatedPrice;
  final String memo;

  const FoodItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.zone,
    required this.registeredDate,
    required this.expiryDate,
    required this.sourceType,
    required this.tip,
    required this.reminderEnabled,
    required this.reminderOffset,
    required this.estimatedPrice,
    required this.memo,
  });

  int get notificationId => id.hashCode.abs() % 2147480000;

  FoodItem copyWith({
    String? id,
    String? name,
    String? emoji,
    String? category,
    String? zone,
    String? registeredDate,
    String? expiryDate,
    String? sourceType,
    String? tip,
    bool? reminderEnabled,
    int? reminderOffset,
    int? estimatedPrice,
    String? memo,
  }) {
    return FoodItem(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      zone: zone ?? this.zone,
      registeredDate: registeredDate ?? this.registeredDate,
      expiryDate: expiryDate ?? this.expiryDate,
      sourceType: sourceType ?? this.sourceType,
      tip: tip ?? this.tip,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderOffset: reminderOffset ?? this.reminderOffset,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      memo: memo ?? this.memo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'category': category,
        'zone': zone,
        'registeredDate': registeredDate,
        'expiryDate': expiryDate,
        'sourceType': sourceType,
        'tip': tip,
        'reminderEnabled': reminderEnabled,
        'reminderOffset': reminderOffset,
        'estimatedPrice': estimatedPrice,
        'memo': memo,
      };

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? '식자재',
      emoji: json['emoji']?.toString() ?? '🥗',
      category: json['category']?.toString() ?? '일반식자재',
      zone: json['zone']?.toString() ?? 'fridge',
      registeredDate: json['registeredDate']?.toString() ?? todayDateStr(),
      expiryDate: json['expiryDate']?.toString() ?? addDaysStr(todayDateStr(), 5),
      sourceType: json['sourceType']?.toString() ?? 'manual',
      tip: json['tip']?.toString() ?? '밀폐 보관해 신선도를 유지하세요.',
      reminderEnabled: json['reminderEnabled'] == true,
      reminderOffset: (json['reminderOffset'] as num?)?.toInt() ?? 3,
      estimatedPrice: (json['estimatedPrice'] as num?)?.toInt() ?? 3500,
      memo: json['memo']?.toString() ?? '',
    );
  }
}

class FoodPreset {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String defaultZone;
  final int fridgeDays;
  final int freezerDays;
  final int roomDays;
  final String fridgeTip;
  final String freezerTip;
  final String roomTip;
  final int estimatedPrice;

  const FoodPreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.defaultZone,
    required this.fridgeDays,
    required this.freezerDays,
    required this.roomDays,
    required this.fridgeTip,
    required this.freezerTip,
    required this.roomTip,
    required this.estimatedPrice,
  });

  int daysForZone(String zone) {
    if (zone == 'freezer') return freezerDays > 0 ? freezerDays : 30;
    if (zone == 'room') return roomDays > 0 ? roomDays : 2;
    return fridgeDays > 0 ? fridgeDays : 5;
  }

  String tipForZone(String zone) {
    if (zone == 'freezer') return freezerTip;
    if (zone == 'room') return roomTip;
    return fridgeTip;
  }
}

class BatchDraftItem {
  bool checked;
  String name;
  String emoji;
  String zone;
  String expiryDate;
  String tip;
  int estimatedPrice;

  BatchDraftItem({
    this.checked = true,
    required this.name,
    required this.emoji,
    required this.zone,
    required this.expiryDate,
    required this.tip,
    required this.estimatedPrice,
  });
}

class RecipeSuggestion {
  final String title;
  final String time;
  final String style;
  final String summary;
  final List<String> usedNames;
  final List<String> extraIngredients;
  final List<String> steps;

  const RecipeSuggestion({
    required this.title,
    required this.time,
    required this.style,
    required this.summary,
    required this.usedNames,
    required this.extraIngredients,
    required this.steps,
  });
}

String formatDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String todayDateStr() => formatDate(DateTime.now());

DateTime parseDateStr(String s) {
  final parts = s.split('-');
  if (parts.length != 3) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  return DateTime(
    int.tryParse(parts[0]) ?? DateTime.now().year,
    int.tryParse(parts[1]) ?? DateTime.now().month,
    int.tryParse(parts[2]) ?? DateTime.now().day,
  );
}

String addDaysStr(String dateStr, int days) {
  final dt = parseDateStr(dateStr).add(Duration(days: days));
  return formatDate(dt);
}

int calcDDay(String expiryDateStr) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final exp = parseDateStr(expiryDateStr);
  return exp.difference(today).inDays;
}

String formatDDayLabel(int dDay) {
  if (dDay == 0) return 'D-Day';
  if (dDay > 0) return 'D-$dDay';
  return 'D+${dDay.abs()}';
}

String zoneLabel(String zone) {
  switch (zone) {
    case 'freezer':
      return '🧊 냉동실';
    case 'room':
      return '🌡️ 실온';
    default:
      return '❄️ 냉장실';
  }
}

String formatWon(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
      buf.write(',');
    }
  }
  return '${buf.toString()}원';
}
