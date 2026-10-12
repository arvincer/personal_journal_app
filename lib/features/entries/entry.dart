enum EntryStatus { draft, published }

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.profileId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.localDate,
    required this.timezoneOffsetMinutes,
    required this.status,
  });

  final String id;
  final String profileId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localDate;
  final int timezoneOffsetMinutes;
  final EntryStatus status;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'profile_id': profileId,
      'text': text,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'local_date': localDate,
      'timezone_offset_minutes': timezoneOffsetMinutes,
      'status': status.name,
    };
  }

  factory JournalEntry.fromMap(Map<String, Object?> map) {
    return JournalEntry(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      text: map['text'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      localDate: map['local_date'] as String,
      timezoneOffsetMinutes: map['timezone_offset_minutes'] as int,
      status: EntryStatus.values.byName(map['status'] as String),
    );
  }
}
