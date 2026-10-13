import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/features/backup/backup_manifest.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:sqflite/sqflite.dart';

typedef RestoreDirectoryProvider = Future<Directory> Function();

abstract interface class BackupRestorer {
  Future<RestorePreview> preview(String archivePath);
  Future<RestoreReport> restore(String archivePath);
}

final class RestoreService implements BackupRestorer {
  RestoreService({
    required this.database,
    required this.snapshotFactory,
    required this.fileStore,
    required this.checksumService,
    required this.temporaryDirectoryProvider,
    this.maximumEntries = 10000,
    this.maximumExpandedBytes = 4 * 1024 * 1024 * 1024,
  });

  final Database database;
  final DatabaseFactory snapshotFactory;
  final AppFileStore fileStore;
  final ChecksumService checksumService;
  final RestoreDirectoryProvider temporaryDirectoryProvider;
  final int maximumEntries;
  final int maximumExpandedBytes;

  @override
  Future<RestorePreview> preview(String archivePath) async {
    final package = await _validate(archivePath);
    try {
      return await _preview(package);
    } finally {
      await package.close();
    }
  }

  @override
  Future<RestoreReport> restore(String archivePath) async {
    final package = await _validate(archivePath);
    final copiedPaths = <String>[];
    try {
      final existingProfileIds = await _existingIds(database, 'profiles');
      final existingEntryIds = await _existingIds(database, 'entries');
      final existingMediaIds = await _existingIds(database, 'media');
      final newProfiles = package.profiles
          .where((row) => !existingProfileIds.contains(row['id']))
          .toList();
      final newEntries = package.entries
          .where((row) => !existingEntryIds.contains(row['id']))
          .toList();
      final newMedia = package.media
          .where((row) => !existingMediaIds.contains(row['id']))
          .toList();

      var insertedProfiles = 0;
      var insertedEntries = 0;
      var insertedMedia = 0;
      await database.transaction((transaction) async {
        for (final row in newProfiles) {
          if (await _insertIgnoring(transaction, 'profiles', row)) {
            insertedProfiles++;
          }
        }
        for (final row in newEntries) {
          if (await _insertIgnoring(transaction, 'entries', row)) {
            insertedEntries++;
          }
        }
        for (final row in newMedia) {
          if (!await _insertIgnoring(transaction, 'media', row)) continue;
          final mediaPaths = <String>[
            row['relative_path']! as String,
            if (row['thumbnail_path'] case final String thumbnail) thumbnail,
          ];
          for (final relativePath in mediaPaths) {
            if (copiedPaths.contains(relativePath)) continue;
            final source = package.file(relativePath);
            await fileStore.restoreFile(source, relativePath);
            copiedPaths.add(relativePath);
          }
          insertedMedia++;
        }
      });
      return RestoreReport(
        insertedProfiles: insertedProfiles,
        insertedEntries: insertedEntries,
        insertedMedia: insertedMedia,
      );
    } catch (error, stackTrace) {
      for (final relativePath in copiedPaths.reversed) {
        try {
          await fileStore.deleteRelative(relativePath);
        } catch (_) {
          // Preserve the restore failure after best-effort compensation.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await package.close();
    }
  }

  Future<_ValidatedPackage> _validate(String archivePath) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw const RestoreValidationException('Backup archive does not exist.');
    }
    final temporaryRoot = await temporaryDirectoryProvider();
    await temporaryRoot.create(recursive: true);
    final staging = Directory(
      path.join(
        temporaryRoot.path,
        'restore-${DateTime.now().microsecondsSinceEpoch}-$pid',
      ),
    );
    await staging.create();
    Database? snapshot;
    InputFileStream? input;
    try {
      input = InputFileStream(archiveFile.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.length > maximumEntries) {
        throw const RestoreValidationException(
          'Backup contains too many files.',
        );
      }
      var expandedBytes = 0;
      final extractedPaths = <String>{};
      for (final entry in archive) {
        final relativePath = _safeArchivePath(entry.name);
        if (!extractedPaths.add(relativePath)) {
          throw RestoreValidationException(
            'Backup contains a duplicate path: $relativePath.',
          );
        }
        if (entry.isSymbolicLink) {
          throw const RestoreValidationException(
            'Backup contains a symbolic link.',
          );
        }
        if (entry.isDirectory) {
          await Directory(path.join(staging.path, relativePath))
              .create(recursive: true);
          continue;
        }
        if (!entry.isFile) {
          throw const RestoreValidationException(
            'Backup contains an unsupported entry type.',
          );
        }
        expandedBytes += entry.size;
        if (expandedBytes > maximumExpandedBytes) {
          throw const RestoreValidationException('Backup is too large.');
        }
        final output = File(path.join(staging.path, relativePath));
        await output.parent.create(recursive: true);
        final outputStream = OutputFileStream(output.path);
        try {
          entry.writeContent(outputStream);
        } finally {
          outputStream.closeSync();
        }
      }
      input.closeSync();
      input = null;

      final manifest = await _readJson(staging, 'manifest.json');
      if (manifest['format_version'] != BackupManifest.currentFormatVersion ||
          manifest['schema_version'] != 1) {
        throw const RestoreValidationException(
          'Backup format or database schema is unsupported.',
        );
      }
      final checksumJson = await _readJson(staging, 'checksums.json');
      final checksums = checksumJson.map(
        (key, value) => MapEntry(key, value as String),
      );
      final actualFiles = await staging
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      final expectedPaths = actualFiles
          .map(
            (file) => path
                .relative(file.path, from: staging.path)
                .replaceAll('\\', '/'),
          )
          .where((value) => value != 'checksums.json')
          .toSet();
      if (checksums.keys.toSet().difference(expectedPaths).isNotEmpty ||
          expectedPaths.difference(checksums.keys.toSet()).isNotEmpty) {
        throw const RestoreValidationException(
          'Backup file list does not match its checksums.',
        );
      }
      for (final MapEntry(:key, :value) in checksums.entries) {
        final file = File(path.join(staging.path, _safeArchivePath(key)));
        if (await checksumService.forFile(file.path) != value) {
          throw RestoreValidationException('Checksum mismatch for $key.');
        }
      }

      final snapshotFile = File(path.join(staging.path, 'backup.sqlite'));
      if (!await snapshotFile.exists()) {
        throw const RestoreValidationException('Backup database is missing.');
      }
      snapshot = await snapshotFactory.openDatabase(
        snapshotFile.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final profiles = await snapshot.query('profiles');
      final entries = await snapshot.query('entries');
      final media = await snapshot.query('media');
      for (final row in media) {
        final referencedPaths = <String>[
          row['relative_path']! as String,
          if (row['thumbnail_path'] case final String thumbnail) thumbnail,
        ];
        for (final relativePath in referencedPaths) {
          final safePath = _safeMediaPath(relativePath);
          if (!await File(path.join(staging.path, safePath)).exists()) {
            throw RestoreValidationException(
              'Referenced media file is missing: $relativePath.',
            );
          }
        }
      }
      return _ValidatedPackage(
        staging: staging,
        snapshot: snapshot,
        profiles: profiles,
        entries: entries,
        media: media,
      );
    } catch (error, stackTrace) {
      input?.closeSync();
      await snapshot?.close();
      if (await staging.exists()) await staging.delete(recursive: true);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<RestorePreview> _preview(_ValidatedPackage package) async {
    final profileIds = await _existingIds(database, 'profiles');
    final entryIds = await _existingIds(database, 'entries');
    final mediaIds = await _existingIds(database, 'media');
    int duplicates(List<Map<String, Object?>> rows, Set<Object?> ids) =>
        rows.where((row) => ids.contains(row['id'])).length;
    final duplicateProfiles = duplicates(package.profiles, profileIds);
    final duplicateEntries = duplicates(package.entries, entryIds);
    final duplicateMedia = duplicates(package.media, mediaIds);
    return RestorePreview(
      newProfiles: package.profiles.length - duplicateProfiles,
      duplicateProfiles: duplicateProfiles,
      newEntries: package.entries.length - duplicateEntries,
      duplicateEntries: duplicateEntries,
      newMedia: package.media.length - duplicateMedia,
      duplicateMedia: duplicateMedia,
      missingFiles: 0,
      damagedFiles: 0,
    );
  }

  Future<Set<Object?>> _existingIds(
    DatabaseExecutor executor,
    String table,
  ) async {
    final rows = await executor.query(table, columns: <String>['id']);
    return rows.map((row) => row['id']).toSet();
  }

  Future<bool> _insertIgnoring(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    await executor.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final changes = await executor.rawQuery('SELECT changes() AS count');
    return changes.single['count'] == 1;
  }

  Future<Map<String, Object?>> _readJson(
    Directory staging,
    String relativePath,
  ) async {
    final file = File(path.join(staging.path, relativePath));
    if (!await file.exists()) {
      throw RestoreValidationException('$relativePath is missing.');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      throw RestoreValidationException('$relativePath is invalid.');
    }
    return value;
  }

  String _safeArchivePath(String value) {
    var normalized = value.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.split('/').any((part) => part.isEmpty || part == '..')) {
      throw RestoreValidationException('Unsafe backup path: $value.');
    }
    return normalized;
  }

  String _safeMediaPath(String value) {
    final normalized = _safeArchivePath(value);
    const allowed = <String>[
      'media/images/',
      'media/videos/',
      'media/thumbnails/',
    ];
    if (!allowed.any(normalized.startsWith)) {
      throw RestoreValidationException('Unsafe media path: $value.');
    }
    return normalized;
  }
}

final class _ValidatedPackage {
  _ValidatedPackage({
    required this.staging,
    required this.snapshot,
    required this.profiles,
    required this.entries,
    required this.media,
  });

  final Directory staging;
  final Database snapshot;
  final List<Map<String, Object?>> profiles;
  final List<Map<String, Object?>> entries;
  final List<Map<String, Object?>> media;

  File file(String relativePath) =>
      File(path.joinAll(<String>[staging.path, ...relativePath.split('/')]));

  Future<void> close() async {
    await snapshot.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
