class RestorePreview {
  const RestorePreview({
    required this.newProfiles,
    required this.duplicateProfiles,
    required this.newEntries,
    required this.duplicateEntries,
    required this.newMedia,
    required this.duplicateMedia,
    required this.missingFiles,
    required this.damagedFiles,
  });

  final int newProfiles;
  final int duplicateProfiles;
  final int newEntries;
  final int duplicateEntries;
  final int newMedia;
  final int duplicateMedia;
  final int missingFiles;
  final int damagedFiles;
}

class RestoreReport {
  const RestoreReport({
    required this.insertedProfiles,
    required this.insertedEntries,
    required this.insertedMedia,
  });

  final int insertedProfiles;
  final int insertedEntries;
  final int insertedMedia;
}

class RestoreValidationException implements Exception {
  const RestoreValidationException(this.message);

  final String message;

  @override
  String toString() => 'RestoreValidationException: $message';
}
