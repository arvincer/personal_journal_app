class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.profileCount,
    required this.entryCount,
    required this.mediaCount,
  });

  static const int currentFormatVersion = 1;

  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final int profileCount;
  final int entryCount;
  final int mediaCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'format_version': currentFormatVersion,
    'app_version': appVersion,
    'schema_version': schemaVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'profile_count': profileCount,
    'entry_count': entryCount,
    'media_count': mediaCount,
  };
}
