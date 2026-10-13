import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/backup/backup_service.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'backs up, restores into a fresh root, and remains idempotent',
    () async {
      final root = await Directory.systemTemp.createTemp('backup-restore-e2e-');
      Directory directory(String name) =>
          Directory(path.join(root.path, name))..createSync(recursive: true);
      final sourceSupport = directory('source-support');
      final sourceTemp = directory('source-temp');
      final targetSupport = directory('target-support');
      final targetTemp = directory('target-temp');
      final source = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path.join(sourceSupport.path, 'journal.db'),
      );
      final target = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path.join(targetSupport.path, 'journal.db'),
      );
      addTearDown(() async {
        await source.close();
        await target.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      await source.insert(
        'profiles',
        Profile(
          id: 'profile',
          name: '我的日志',
          avatarPath: null,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          isDefault: true,
          isArchived: false,
        ).toMap(),
      );
      await source.insert(
        'entries',
        JournalEntry(
          id: 'entry',
          profileId: 'profile',
          text: '记录',
          createdAt: DateTime.utc(2026, 10, 13),
          updatedAt: DateTime.utc(2026, 10, 13),
          localDate: '2026-10-13',
          timezoneOffsetMinutes: 480,
          status: EntryStatus.published,
        ).toMap(),
      );
      const relativePath = 'media/images/photo.jpg';
      final sourceMedia = File(path.join(sourceSupport.path, relativePath));
      await sourceMedia.parent.create(recursive: true);
      await sourceMedia.writeAsString('stable media bytes');
      final checksum = await Sha256ChecksumService().forFile(sourceMedia.path);
      await source.insert(
        'media',
        MediaItem(
          id: 'photo',
          entryId: 'entry',
          type: MediaType.image,
          relativePath: relativePath,
          thumbnailPath: null,
          originalFilename: 'photo.jpg',
          mimeType: 'image/jpeg',
          fileSize: await sourceMedia.length(),
          width: 10,
          height: 10,
          durationMilliseconds: null,
          caption: null,
          checksumSha256: checksum,
          createdAt: DateTime.utc(2026, 10, 13),
        ).toMap(),
      );
      final archive =
          await BackupService(
            database: source,
            snapshotFactory: databaseFactoryFfi,
            fileStore: AppFileStore(
              supportDirectoryProvider: () async => sourceSupport,
              temporaryDirectoryProvider: () async => sourceTemp,
            ),
            checksumService: Sha256ChecksumService(),
            zipService: const ZipService(),
            temporaryDirectoryProvider: () async => sourceTemp,
          ).createFullBackup(
            destinationPath: path.join(root.path, 'backup.zip'),
            appVersion: '1.0.0',
          );
      final restorer = RestoreService(
        database: target,
        snapshotFactory: databaseFactoryFfi,
        fileStore: AppFileStore(
          supportDirectoryProvider: () async => targetSupport,
          temporaryDirectoryProvider: () async => targetTemp,
        ),
        checksumService: Sha256ChecksumService(),
        temporaryDirectoryProvider: () async => targetTemp,
      );

      final first = await restorer.restore(archive.path);
      expect(first.insertedProfiles, 1);
      expect(first.insertedEntries, 1);
      expect(first.insertedMedia, 1);
      expect(await _counts(target), <int>[1, 1, 1]);
      expect(
        await Sha256ChecksumService().forFile(
          path.join(targetSupport.path, relativePath),
        ),
        checksum,
      );

      final second = await restorer.restore(archive.path);
      expect(second.insertedProfiles, 0);
      expect(second.insertedEntries, 0);
      expect(second.insertedMedia, 0);
      expect(await _counts(target), <int>[1, 1, 1]);
    },
  );
}

Future<List<int>> _counts(Database database) async => <int>[
  for (final table in <String>['profiles', 'entries', 'media'])
    (await database.rawQuery('SELECT COUNT(*) FROM $table'))
            .single
            .values
            .single!
        as int,
];
