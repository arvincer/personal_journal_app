import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/time/clock.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('SqliteEntryRepository', () {
    late Database database;
    late SqliteEntryRepository repository;
    late _Sequence<String> ids;
    late _FixedClock clock;

    setUp(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await _insertProfile(database, 'one');
      await _insertProfile(database, 'two');
      ids = _Sequence<String>(<String>[
        'draft-one',
        'draft-two',
        'range-one',
        'range-two',
        'range-three',
      ]);
      clock = _FixedClock(DateTime(2026, 10, 12, 23, 30));
      repository = SqliteEntryRepository(
        database,
        clock: clock,
        idProvider: ids.next,
      );
    });

    tearDown(() => database.close());

    test(
      'drafts are isolated by profile and only one draft is retained',
      () async {
        await repository.saveDraft(profileId: 'one', text: 'first');
        await repository.saveDraft(profileId: 'two', text: 'second');
        await Future.wait(<Future<JournalEntry>>[
          repository.saveDraft(profileId: 'one', text: 'latest'),
          repository.saveDraft(profileId: 'one', text: 'latest again'),
        ]);

        expect((await repository.getDraft('one'))!.text, 'latest again');
        expect((await repository.getDraft('two'))!.text, 'second');
        expect(
          await database.query(
            'entries',
            where: 'profile_id = ? AND status = ?',
            whereArgs: <Object?>['one', 'draft'],
          ),
          hasLength(1),
        );
      },
    );

    test(
      'publishing stores the local day and offset from the injected clock',
      () async {
        await repository.saveDraft(profileId: 'one', text: 'Night note');

        final published = await repository.publishDraft('one');

        expect(published.status, EntryStatus.published);
        expect(published.createdAt, DateTime.utc(2026, 10, 12, 15, 30));
        expect(published.updatedAt, DateTime.utc(2026, 10, 12, 15, 30));
        expect(published.localDate, '2026-10-12');
        expect(published.timezoneOffsetMinutes, 480);
      },
    );

    test('listDay returns published entries in newest-first order', () async {
      await repository.saveDraft(profileId: 'one', text: 'older');
      final older = await repository.publishDraft('one');
      clock.now = DateTime(2026, 10, 12, 23, 31);
      await repository.saveDraft(profileId: 'one', text: 'newer');
      final newer = await repository.publishDraft('one');
      await repository.saveDraft(profileId: 'one', text: 'draft only');

      final entries = await repository.listDay('one', DateTime(2026, 10, 12));

      expect(entries.map((entry) => entry.id), <String>[newer.id, older.id]);
    });

    test(
      'listRange includes boundary days across requested profiles stably',
      () async {
        await repository.saveDraft(profileId: 'one', text: 'start');
        final start = await repository.publishDraft('one');
        clock.now = DateTime(2026, 10, 13, 9);
        await repository.saveDraft(profileId: 'two', text: 'middle');
        final middle = await repository.publishDraft('two');
        clock.now = DateTime(2026, 10, 14, 9);
        await repository.saveDraft(profileId: 'one', text: 'end');
        final end = await repository.publishDraft('one');

        final entries = await repository.listRange(
          profileIds: <String>['two', 'one'],
          from: DateTime(2026, 10, 12),
          to: DateTime(2026, 10, 14),
        );

        expect(entries.map((entry) => entry.id), <String>[
          end.id,
          middle.id,
          start.id,
        ]);
      },
    );

    test('blank draft cannot publish unless it has media', () async {
      final draft = await repository.saveDraft(profileId: 'one', text: '  ');

      await expectLater(repository.publishDraft('one'), throwsStateError);
      await _insertMedia(database, entryId: draft.id);

      expect(
        (await repository.publishDraft('one')).status,
        EntryStatus.published,
      );
    });

    test('published text cannot become blank without media', () async {
      await repository.saveDraft(profileId: 'one', text: 'Text');
      final entry = await repository.publishDraft('one');

      await expectLater(
        repository.updateText(entryId: entry.id, text: ' \n '),
        throwsStateError,
      );
      await _insertMedia(database, entryId: entry.id);
      await repository.updateText(entryId: entry.id, text: ' \n ');

      expect(
        (await repository.listDay('one', DateTime(2026, 10, 12))).single.text,
        ' \n ',
      );
    });

    test('deleteEntry cascades to media rows', () async {
      await repository.saveDraft(profileId: 'one', text: 'Text');
      final entry = await repository.publishDraft('one');
      await _insertMedia(database, entryId: entry.id);

      await repository.deleteEntry(entry.id);

      expect(await database.query('entries'), isEmpty);
      expect(await database.query('media'), isEmpty);
    });
  });
}

Future<void> _insertProfile(Database database, String id) {
  return database
      .insert(
        'profiles',
        Profile(
          id: id,
          name: id,
          avatarPath: null,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          isDefault: id == 'one',
          isArchived: false,
        ).toMap(),
      )
      .then((_) {});
}

Future<void> _insertMedia(Database database, {required String entryId}) async {
  await database.insert('media', <String, Object?>{
    'id': 'media-$entryId',
    'entry_id': entryId,
    'type': 'image',
    'relative_path': 'media/$entryId.jpg',
    'thumbnail_path': null,
    'original_filename': 'entry.jpg',
    'mime_type': 'image/jpeg',
    'file_size': 1,
    'width': null,
    'height': null,
    'duration_ms': null,
    'caption': null,
    'checksum_sha256': 'checksum-$entryId',
    'created_at': DateTime.utc(2026).toIso8601String(),
  });
}

final class _FixedClock implements Clock {
  _FixedClock(this.now);

  @override
  DateTime now;

  @override
  int get utcOffsetMinutes => 480;
}

final class _Sequence<T> {
  _Sequence(this._values);

  final List<T> _values;
  int _index = 0;

  T next() => _values[_index++];
}
