import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/backup/backup_service.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('previews, restores, and skips repeated UUIDs', () async {
    final fixture = await _RestoreFixture.create();
    addTearDown(fixture.close);
    final archive = await fixture.createBackup();

    final preview = await fixture.restoreService.preview(archive.path);
    expect(preview.newProfiles, 1);
    expect(preview.newEntries, 1);
    expect(preview.newMedia, 1);
    expect(preview.duplicateProfiles, 0);
    expect(preview.missingFiles, 0);
    expect(preview.damagedFiles, 0);

    final first = await fixture.restoreService.restore(archive.path);
    expect(first.insertedProfiles, 1);
    expect(first.insertedEntries, 1);
    expect(first.insertedMedia, 1);
    expect(await fixture.targetCount('profiles'), 1);
    expect(await fixture.targetCount('entries'), 1);
    expect(await fixture.targetCount('media'), 1);
    expect(
      await File(
        path.join(fixture.targetSupport.path, 'media/images/photo.jpg'),
      ).readAsString(),
      'photo bytes',
    );

    final repeatedPreview = await fixture.restoreService.preview(archive.path);
    expect(repeatedPreview.duplicateProfiles, 1);
    expect(repeatedPreview.duplicateEntries, 1);
    expect(repeatedPreview.duplicateMedia, 1);
    final repeated = await fixture.restoreService.restore(archive.path);
    expect(repeated.insertedProfiles, 0);
    expect(repeated.insertedEntries, 0);
    expect(repeated.insertedMedia, 0);
  });

  test('rejects a database reference whose media file is missing', () async {
    final fixture = await _RestoreFixture.create();
    addTearDown(fixture.close);
    final archive = await fixture.createBackup();
    final missingMediaArchive = await _removeArchiveEntry(
      archive,
      'media/images/photo.jpg',
      path.join(fixture.root.path, 'missing-media.zip'),
    );

    await expectLater(
      fixture.restoreService.preview(missingMediaArchive.path),
      throwsA(isA<RestoreValidationException>()),
    );

    expect(await fixture.targetTemporary.list().toList(), isEmpty);
  });

  test('rolls back rows and copied media when a later copy fails', () async {
    final fixture = await _RestoreFixture.create();
    addTearDown(fixture.close);
    await fixture.addVideo();
    final archive = await fixture.createBackup();
    await Directory(
      path.join(fixture.targetSupport.path, 'media/videos/video.mp4'),
    ).create(recursive: true);

    await expectLater(
      fixture.restoreService.restore(archive.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(await fixture.targetCount('profiles'), 0);
    expect(await fixture.targetCount('entries'), 0);
    expect(await fixture.targetCount('media'), 0);
    expect(
      await File(
        path.join(fixture.targetSupport.path, 'media/images/photo.jpg'),
      ).exists(),
      isFalse,
    );
  });
}

Future<File> _removeArchiveEntry(
  File source,
  String removedPath,
  String destination,
) async {
  final decoded = ZipDecoder().decodeBytes(await source.readAsBytes());
  final files = <String, List<int>>{
    for (final entry in decoded.files)
      if (entry.isFile &&
          entry.name != removedPath &&
          entry.name != 'checksums.json')
        entry.name: entry.content,
  };
  files['checksums.json'] = utf8.encode(
    jsonEncode(<String, String>{
      for (final entry in files.entries)
        entry.key: sha256.convert(entry.value).toString(),
    }),
  );
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return File(destination)
      .writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
}

final class _RestoreFixture {
  _RestoreFixture({
    required this.root,
    required this.sourceSupport,
    required this.sourceTemporary,
    required this.targetSupport,
    required this.targetTemporary,
    required this.sourceDatabase,
    required this.targetDatabase,
  });

  final Directory root;
  final Directory sourceSupport;
  final Directory sourceTemporary;
  final Directory targetSupport;
  final Directory targetTemporary;
  final Database sourceDatabase;
  final Database targetDatabase;

  static Future<_RestoreFixture> create() async {
    final root = await Directory.systemTemp.createTemp('journal-restore-test-');
    Directory directory(String name) =>
        Directory(path.join(root.path, name))..createSync(recursive: true);
    final sourceSupport = directory('source-support');
    final sourceTemporary = directory('source-temp');
    final targetSupport = directory('target-support');
    final targetTemporary = directory('target-temp');
    final sourceDatabase = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(sourceSupport.path, 'journal.db'),
    );
    final targetDatabase = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(targetSupport.path, 'journal.db'),
    );
    final profile = Profile(
      id: 'profile',
      name: 'Me',
      avatarPath: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      isDefault: true,
      isArchived: false,
    );
    final entry = JournalEntry(
      id: 'entry',
      profileId: profile.id,
      text: 'journal',
      createdAt: DateTime.utc(2026, 10, 13),
      updatedAt: DateTime.utc(2026, 10, 13),
      localDate: '2026-10-13',
      timezoneOffsetMinutes: 480,
      status: EntryStatus.published,
    );
    final media = MediaItem(
      id: 'photo',
      entryId: entry.id,
      type: MediaType.image,
      relativePath: 'media/images/photo.jpg',
      thumbnailPath: null,
      originalFilename: 'photo.jpg',
      mimeType: 'image/jpeg',
      fileSize: 11,
      width: 10,
      height: 10,
      durationMilliseconds: null,
      caption: null,
      checksumSha256: 'source',
      createdAt: DateTime.utc(2026, 10, 13),
    );
    await sourceDatabase.insert('profiles', profile.toMap());
    await sourceDatabase.insert('entries', entry.toMap());
    await sourceDatabase.insert('media', media.toMap());
    final mediaFile = File(
      path.join(sourceSupport.path, 'media/images/photo.jpg'),
    );
    await mediaFile.parent.create(recursive: true);
    await mediaFile.writeAsString('photo bytes');
    return _RestoreFixture(
      root: root,
      sourceSupport: sourceSupport,
      sourceTemporary: sourceTemporary,
      targetSupport: targetSupport,
      targetTemporary: targetTemporary,
      sourceDatabase: sourceDatabase,
      targetDatabase: targetDatabase,
    );
  }

  RestoreService get restoreService => RestoreService(
    database: targetDatabase,
    snapshotFactory: databaseFactoryFfi,
    fileStore: AppFileStore(
      supportDirectoryProvider: () async => targetSupport,
      temporaryDirectoryProvider: () async => targetTemporary,
    ),
    checksumService: Sha256ChecksumService(),
    temporaryDirectoryProvider: () async => targetTemporary,
  );

  Future<File> createBackup() =>
      BackupService(
        database: sourceDatabase,
        snapshotFactory: databaseFactoryFfi,
        fileStore: AppFileStore(
          supportDirectoryProvider: () async => sourceSupport,
          temporaryDirectoryProvider: () async => sourceTemporary,
        ),
        checksumService: Sha256ChecksumService(),
        zipService: const ZipService(),
        temporaryDirectoryProvider: () async => sourceTemporary,
      ).createFullBackup(
        destinationPath: path.join(root.path, 'backup.zip'),
        appVersion: '1.0.0',
      );

  Future<void> addVideo() async {
    final video = MediaItem(
      id: 'video',
      entryId: 'entry',
      type: MediaType.video,
      relativePath: 'media/videos/video.mp4',
      thumbnailPath: 'media/thumbnails/video.jpg',
      originalFilename: 'video.mp4',
      mimeType: 'video/mp4',
      fileSize: 11,
      width: 10,
      height: 10,
      durationMilliseconds: 1000,
      caption: null,
      checksumSha256: 'source',
      createdAt: DateTime.utc(2026, 10, 13),
    );
    await sourceDatabase.insert('media', video.toMap());
    final videoFile = File(path.join(sourceSupport.path, video.relativePath));
    await videoFile.parent.create(recursive: true);
    await videoFile.writeAsString('video bytes');
    final thumbnail = File(path.join(sourceSupport.path, video.thumbnailPath!));
    await thumbnail.parent.create(recursive: true);
    await thumbnail.writeAsString('thumbnail bytes');
  }

  Future<int> targetCount(String table) async =>
      (await targetDatabase.rawQuery('SELECT COUNT(*) FROM $table'))
              .single
              .values
              .single!
          as int;

  Future<void> close() async {
    await sourceDatabase.close();
    await targetDatabase.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
