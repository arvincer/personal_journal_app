import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/core/time/clock.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/export/analysis_export_service.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/export/markdown_renderer.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('records isolated profiles, browses, edits, and exports', () async {
    final root = await Directory.systemTemp.createTemp('journal-e2e-');
    final support = Directory(path.join(root.path, 'support'))
      ..createSync(recursive: true);
    final temporary = Directory(path.join(root.path, 'temporary'))
      ..createSync(recursive: true);
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path.join(support.path, 'journal.db'),
    );
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final profileIds = <String>['me', 'child'].iterator;
    String nextProfileId() {
      profileIds.moveNext();
      return profileIds.current;
    }

    final profiles = SqliteProfileRepository(
      database,
      idProvider: nextProfileId,
      nowProvider: () => DateTime.utc(2026, 10, 13),
    );
    final controller = ProfileController(profiles);
    addTearDown(controller.close);
    await controller.initialize();
    final me = controller.active!;
    final child = await controller.createAndSelect('孩子');
    expect(controller.active?.id, child.id);

    final entryIds = <String>['me-entry', 'child-entry'].iterator;
    String nextEntryId() {
      entryIds.moveNext();
      return entryIds.current;
    }

    final entries = SqliteEntryRepository(
      database,
      clock: _FixedClock(),
      idProvider: nextEntryId,
    );
    final media = SqliteMediaRepository(database);
    final meDraft = await entries.saveDraft(profileId: me.id, text: '我的记录');
    await _addFixtureMedia(
      support: support,
      repository: media,
      entryId: meDraft.id,
      id: 'me-photo',
      relativePath: 'media/images/me-photo.jpg',
    );
    final meEntry = await entries.publishDraft(me.id);
    final childDraft = await entries.saveDraft(
      profileId: child.id,
      text: '孩子的记录',
    );
    await _addFixtureMedia(
      support: support,
      repository: media,
      entryId: childDraft.id,
      id: 'child-photo',
      relativePath: 'media/images/child-photo.jpg',
    );
    await entries.publishDraft(child.id);

    await controller.select(me.id);
    expect((await entries.listDay(me.id, DateTime(2026, 10, 13))).length, 1);
    expect(
      (await entries.listDay(child.id, DateTime(2026, 10, 13))).single.text,
      '孩子的记录',
    );
    expect(
      await entries.countByDay(
        me.id,
        DateTime(2026, 10),
        DateTime(2026, 10, 31),
      ),
      <String, int>{'2026-10-13': 1},
    );

    await entries.updateText(entryId: meEntry.id, text: '修改后的记录');
    final edited = (await entries.listDay(
      me.id,
      DateTime(2026, 10, 13),
    )).single;
    expect(edited.text, '修改后的记录');
    expect(edited.createdAt, meEntry.createdAt);

    final destination = path.join(root.path, 'analysis.zip');
    await AnalysisExportService(
      entryRepository: entries,
      mediaRepository: media,
      fileStore: AppFileStore(
        supportDirectoryProvider: () async => support,
        temporaryDirectoryProvider: () async => temporary,
      ),
      zipService: const ZipService(),
      markdownRenderer: MarkdownRenderer(),
      temporaryDirectoryProvider: () async => temporary,
    ).create(
      request: AnalysisExportRequest(
        profileIds: <String>{me.id, child.id},
        from: DateTime(2026, 10, 13),
        to: DateTime(2026, 10, 13),
        includeOriginalVideos: false,
      ),
      profiles: controller.profiles,
      appVersion: '1.0.0',
      destinationPath: destination,
    );
    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, contains('profiles/me/days/2026-10-13.md'));
    expect(names, contains('profiles/child/days/2026-10-13.md'));
  });
}

Future<void> _addFixtureMedia({
  required Directory support,
  required SqliteMediaRepository repository,
  required String entryId,
  required String id,
  required String relativePath,
}) async {
  final file = File(
    path.joinAll(<String>[support.path, ...relativePath.split('/')]),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString('$id bytes');
  await repository.insert(
    MediaItem(
      id: id,
      entryId: entryId,
      type: MediaType.image,
      relativePath: relativePath,
      thumbnailPath: null,
      originalFilename: path.basename(relativePath),
      mimeType: 'image/jpeg',
      fileSize: await file.length(),
      width: 10,
      height: 10,
      durationMilliseconds: null,
      caption: null,
      checksumSha256: 'fixture',
      createdAt: DateTime.utc(2026, 10, 13),
    ),
  );
}

final class _FixedClock implements Clock {
  @override
  DateTime get now => DateTime(2026, 10, 13, 9, 20);

  @override
  int get utcOffsetMinutes => 480;
}
