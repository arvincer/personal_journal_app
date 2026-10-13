import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/backup/backup_manifest.dart';
import 'package:sqflite/sqflite.dart';

typedef BackupDirectoryProvider = Future<Directory> Function();
typedef BackupCreatedAtProvider = DateTime Function();

final class BackupService {
  BackupService({
    required this.database,
    required this.snapshotFactory,
    required this.fileStore,
    required this.checksumService,
    required this.zipService,
    required this.temporaryDirectoryProvider,
    BackupCreatedAtProvider? createdAtProvider,
  }) : _createdAtProvider = createdAtProvider ?? DateTime.now;

  final Database database;
  final DatabaseFactory snapshotFactory;
  final AppFileStore fileStore;
  final ChecksumService checksumService;
  final ZipService zipService;
  final BackupDirectoryProvider temporaryDirectoryProvider;
  final BackupCreatedAtProvider _createdAtProvider;

  Future<File> createFullBackup({
    required String destinationPath,
    required String appVersion,
  }) async {
    final temporaryRoot = await temporaryDirectoryProvider();
    await temporaryRoot.create(recursive: true);
    final staging = Directory(
      path.join(
        temporaryRoot.path,
        'full-backup-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create();
    Database? snapshotDatabase;
    try {
      final snapshot = File(path.join(staging.path, 'backup.sqlite'));
      await database.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await database.execute(
        "VACUUM INTO '${snapshot.path.replaceAll("'", "''")}'",
      );
      snapshotDatabase = await snapshotFactory.openDatabase(
        snapshot.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final profileCount = await _count(snapshotDatabase, 'profiles');
      final entryCount = await _count(snapshotDatabase, 'entries');
      final mediaRows = await snapshotDatabase.query('media');
      final mediaPaths = <String>{};
      for (final row in mediaRows) {
        mediaPaths.add(row['relative_path']! as String);
        final thumbnail = row['thumbnail_path'] as String?;
        if (thumbnail != null) mediaPaths.add(thumbnail);
      }
      await snapshotDatabase.close();
      snapshotDatabase = null;

      for (final relativePath in mediaPaths.toList()..sort()) {
        await _copyMedia(staging, relativePath);
      }
      final manifest = BackupManifest(
        appVersion: appVersion,
        schemaVersion: 1,
        createdAt: _createdAtProvider(),
        profileCount: profileCount,
        entryCount: entryCount,
        mediaCount: mediaRows.length,
      );
      await _writeJson(
        File(path.join(staging.path, 'manifest.json')),
        manifest.toJson(),
      );
      final checksums = await _checksums(staging);
      await _writeJson(
        File(path.join(staging.path, 'checksums.json')),
        checksums,
      );
      return await zipService.create(
        stagingDirectory: staging,
        destinationPath: destinationPath,
      );
    } finally {
      await snapshotDatabase?.close();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<int> _count(Database database, String table) async {
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $table',
    );
    return rows.single['count']! as int;
  }

  Future<void> _copyMedia(Directory staging, String relativePath) async {
    final source = await fileStore.resolve(relativePath);
    if (!await source.exists()) {
      throw FileSystemException('Backup media is missing.', source.path);
    }
    final target = File(
      path.joinAll(<String>[staging.path, ...relativePath.split('/')]),
    );
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }

  Future<Map<String, String>> _checksums(Directory staging) async {
    final files = await staging
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    return <String, String>{
      for (final file in files)
        path.relative(file.path, from: staging.path).replaceAll('\\', '/'):
            await checksumService.forFile(file.path),
    };
  }

  Future<void> _writeJson(File file, Map<String, Object?> value) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }
}
