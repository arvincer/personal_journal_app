class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    required this.isDefault,
    required this.isArchived,
  });

  final String id;
  final String name;
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDefault;
  final bool isArchived;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'avatar_path': avatarPath,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_default': isDefault ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
    };
  }

  factory Profile.fromMap(Map<String, Object?> map) {
    return Profile(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarPath: map['avatar_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      isDefault: _decodeSqliteBoolean(map['is_default'], 'is_default'),
      isArchived: _decodeSqliteBoolean(map['is_archived'], 'is_archived'),
    );
  }
}

bool _decodeSqliteBoolean(Object? value, String fieldName) {
  if (value is! int || (value != 0 && value != 1)) {
    throw FormatException(
      'Expected $fieldName to be the SQLite integer 0 or 1, got $value.',
    );
  }
  return value == 1;
}
