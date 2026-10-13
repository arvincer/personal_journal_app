import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/backup/backup_service.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates a full backup with verified snapshot and media', () async {
    final root = await Directory.systemTemp.createTemp('journal-backup-test-');
    final support = Directory(path.join(root.path, 'support'))..createSync();
    final temporary = Directory(path.join(root.path, 'temporary'))
      ..createSync();
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(support.path, 'journal.db'),
    );
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final profile = _profile();
    final entry = _entry();
    final image = _media(
      id: 'image',
      type: MediaType.image,
      relativePath: 'media/images/image.jpg',
    );
    final video = _media(
      id: 'video',
      type: MediaType.video,
      relativePath: 'media/videos/video.mp4',
      thumbnailPath: 'media/thumbnails/video.jpg',
    );
    await database.insert('profiles', profile.toMap());
    await database.insert('entries', entry.toMap());
    await database.insert('media', image.toMap());
    await database.insert('media', video.toMap());
    await _write(support, image.relativePath, 'image bytes');
    await _write(support, video.relativePath, 'video bytes');
    await _write(support, video.thumbnailPath!, 'thumbnail bytes');
    final destination = path.join(root.path, 'backup.zip');

    await BackupService(
      database: database,
      snapshotFactory: databaseFactoryFfi,
      fileStore: AppFileStore(
        supportDirectoryProvider: () async => support,
        temporaryDirectoryProvider: () async => temporary,
      ),
      checksumService: Sha256ChecksumService(),
      zipService: const ZipService(),
      temporaryDirectoryProvider: () async => temporary,
      createdAtProvider: () => DateTime.utc(2026, 10, 13, 8),
    ).createFullBackup(destinationPath: destination, appVersion: '1.0.0');

    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    final names = archive.files.where((file) => file.isFile).map((e) => e.name);
    expect(
      names,
      containsAll(<String>[
        'backup.sqlite',
        'media/images/image.jpg',
        'media/videos/video.mp4',
        'media/thumbnails/video.jpg',
        'manifest.json',
        'checksums.json',
      ]),
    );
    final manifest = jsonDecode(_text(archive, 'manifest.json')) as Map;
    expect(manifest['format_version'], 1);
    expect(manifest['schema_version'], 1);
    expect(manifest['profile_count'], 1);
    expect(manifest['entry_count'], 1);
    expect(manifest['media_count'], 2);
    final checksums = (jsonDecode(_text(archive, 'checksums.json')) as Map)
        .cast<String, String>();
    for (final MapEntry(:key, :value) in checksums.entries) {
      final bytes = archive.findFile(key)!.content as List<int>;
      expect(sha256.convert(bytes).toString(), value, reason: key);
    }
    final extractedSnapshot = File(path.join(root.path, 'restored.sqlite'));
    await extractedSnapshot.writeAsBytes(
      archive.findFile('backup.sqlite')!.content as List<int>,
      flush: true,
    );
    final restoredDatabase = await databaseFactoryFfi.openDatabase(
      extractedSnapshot.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    expect(
      (await restoredDatabase.rawQuery('SELECT COUNT(*) FROM profiles'))
          .single
          .values
          .single,
      1,
    );
    expect(
      (await restoredDatabase.rawQuery('SELECT COUNT(*) FROM media'))
          .single
          .values
          .single,
      2,
    );
    await restoredDatabase.close();
    expect(await temporary.list().toList(), isEmpty);
  });

  test('missing media fails without publishing a partial backup', () async {
    final root = await Directory.systemTemp.createTemp('journal-backup-test-');
    final support = Directory(path.join(root.path, 'support'))..createSync();
    final temporary = Directory(path.join(root.path, 'temporary'))
      ..createSync();
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(support.path, 'journal.db'),
    );
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    await database.insert('profiles', _profile().toMap());
    await database.insert('entries', _entry().toMap());
    await database.insert(
      'media',
      _media(
        id: 'missing',
        type: MediaType.image,
        relativePath: 'media/images/missing.jpg',
      ).toMap(),
    );
    final destination = path.join(root.path, 'backup.zip');

    await expectLater(
      BackupService(
        database: database,
        snapshotFactory: databaseFactoryFfi,
        fileStore: AppFileStore(
          supportDirectoryProvider: () async => support,
          temporaryDirectoryProvider: () async => temporary,
        ),
        checksumService: Sha256ChecksumService(),
        zipService: const ZipService(),
        temporaryDirectoryProvider: () async => temporary,
      ).createFullBackup(destinationPath: destination, appVersion: '1.0.0'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await File(destination).exists(), isFalse);
    expect(await temporary.list().toList(), isEmpty);
  });
}

Future<void> _write(Directory root, String relative, String value) async {
  final file = File(path.joinAll(<String>[root.path, ...relative.split('/')]));
  await file.parent.create(recursive: true);
  await file.writeAsString(value);
}

String _text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content as List<int>);

Profile _profile() => Profile(
  id: 'profile',
  name: '我的日志',
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: true,
  isArchived: false,
);

JournalEntry _entry() => JournalEntry(
  id: 'entry',
  profileId: 'profile',
  text: '记录',
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: DateTime.utc(2026, 10, 12),
  localDate: '2026-10-12',
  timezoneOffsetMinutes: 480,
  status: EntryStatus.published,
);

MediaItem _media({
  required String id,
  required MediaType type,
  required String relativePath,
  String? thumbnailPath,
}) => MediaItem(
  id: id,
  entryId: 'entry',
  type: type,
  relativePath: relativePath,
  thumbnailPath: thumbnailPath,
  originalFilename: path.basename(relativePath),
  mimeType: type == MediaType.image ? 'image/jpeg' : 'video/mp4',
  fileSize: 11,
  width: 10,
  height: 10,
  durationMilliseconds: type == MediaType.video ? 1000 : null,
  caption: null,
  checksumSha256: 'source-hash',
  createdAt: DateTime.utc(2026, 10, 12),
);
