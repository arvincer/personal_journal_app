import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('rejects path traversal without writing outside staging', () async {
    final fixture = await _SecurityFixture.create();
    addTearDown(fixture.close);
    final archive = await fixture.writeArchive(
      Archive()..addFile(ArchiveFile.bytes('../escape.txt', <int>[1])),
      'traversal.zip',
    );

    await expectLater(
      fixture.service.preview(archive.path),
      throwsA(isA<RestoreValidationException>()),
    );

    expect(
      await File(path.join(fixture.root.path, 'escape.txt')).exists(),
      isFalse,
    );
    expect(await fixture.temporary.list().toList(), isEmpty);
  });

  test('rejects a bad checksum and cleans extracted files', () async {
    final fixture = await _SecurityFixture.create();
    addTearDown(fixture.close);
    final manifest = utf8.encode(
      jsonEncode(<String, Object?>{'format_version': 1, 'schema_version': 1}),
    );
    final database = <int>[1, 2, 3];
    final checksums = utf8.encode(
      jsonEncode(<String, String>{
        'manifest.json': sha256.convert(manifest).toString(),
        'backup.sqlite': 'not-the-real-checksum',
      }),
    );
    final archive = await fixture.writeArchive(
      Archive()
        ..addFile(ArchiveFile.bytes('manifest.json', manifest))
        ..addFile(ArchiveFile.bytes('backup.sqlite', database))
        ..addFile(ArchiveFile.bytes('checksums.json', checksums)),
      'bad-checksum.zip',
    );

    await expectLater(
      fixture.service.preview(archive.path),
      throwsA(isA<RestoreValidationException>()),
    );

    expect(await fixture.temporary.list().toList(), isEmpty);
  });

  test('rejects an unsupported schema before opening the database', () async {
    final fixture = await _SecurityFixture.create();
    addTearDown(fixture.close);
    final manifest = utf8.encode(
      jsonEncode(<String, Object?>{'format_version': 1, 'schema_version': 99}),
    );
    final archive = await fixture.writeArchive(
      Archive()..addFile(ArchiveFile.bytes('manifest.json', manifest)),
      'future-schema.zip',
    );

    await expectLater(
      fixture.service.preview(archive.path),
      throwsA(isA<RestoreValidationException>()),
    );
  });
}

final class _SecurityFixture {
  _SecurityFixture({
    required this.root,
    required this.support,
    required this.temporary,
    required this.database,
  });

  final Directory root;
  final Directory support;
  final Directory temporary;
  final Database database;

  static Future<_SecurityFixture> create() async {
    final root = await Directory.systemTemp.createTemp('restore-security-');
    final support = Directory(path.join(root.path, 'support'))
      ..createSync(recursive: true);
    final temporary = Directory(path.join(root.path, 'temporary'))
      ..createSync(recursive: true);
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(support.path, 'journal.db'),
    );
    return _SecurityFixture(
      root: root,
      support: support,
      temporary: temporary,
      database: database,
    );
  }

  RestoreService get service => RestoreService(
    database: database,
    snapshotFactory: databaseFactoryFfi,
    fileStore: AppFileStore(
      supportDirectoryProvider: () async => support,
      temporaryDirectoryProvider: () async => temporary,
    ),
    checksumService: Sha256ChecksumService(),
    temporaryDirectoryProvider: () async => temporary,
  );

  Future<File> writeArchive(Archive archive, String filename) async =>
      File(path.join(root.path, filename))
          .writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);

  Future<void> close() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
