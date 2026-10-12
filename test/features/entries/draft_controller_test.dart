import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/time/clock.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('DraftController', () {
    late Database database;
    late SqliteEntryRepository repository;

    setUp(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await _insertProfile(database, 'one');
      await _insertProfile(database, 'two');
      repository = SqliteEntryRepository(
        database,
        clock: _FixedClock(DateTime(2026, 10, 12, 9)),
        idProvider: _IdSequence().next,
      );
    });

    tearDown(() => database.close());

    test('debounces editor changes into a saved draft', () async {
      final controller = DraftController(repository);
      await controller.initialize('one');

      controller.textController.text = 'Saved after debounce';
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect((await repository.getDraft('one'))!.text, 'Saved after debounce');
      await controller.close();
    });

    test(
      'switchProfile flushes the previous profile before loading the next',
      () async {
        final controller = DraftController(repository);
        await controller.initialize('one');
        controller.textController.text = 'First profile text';

        await controller.switchProfile('two');

        expect((await repository.getDraft('one'))!.text, 'First profile text');
        expect(controller.profileId, 'two');
        expect(controller.textController.text, '');
        await controller.close();
      },
    );

    test(
      'publish flushes, publishes, and starts a fresh empty draft',
      () async {
        final controller = DraftController(repository);
        await controller.initialize('one');
        controller.textController.text = 'Publish this';

        final published = await controller.publish();

        expect(published.text, 'Publish this');
        expect(controller.textController.text, '');
        expect((await repository.getDraft('one'))!.text, '');
        await controller.close();
      },
    );

    test(
      'close waits for a pending save and prevents later notifications',
      () async {
        final controller = DraftController(repository);
        var notifications = 0;
        controller.addListener(() => notifications++);
        await controller.initialize('one');
        final beforeClose = notifications;
        controller.textController.text = 'Persist before closing';

        await controller.close();

        expect(
          (await repository.getDraft('one'))!.text,
          'Persist before closing',
        );
        expect(notifications, beforeClose);
      },
    );

    test('close rejects operations queued after shutdown starts', () async {
      final controller = DraftController(repository);
      await controller.initialize('one');

      final close = controller.close();

      await expectLater(controller.flush(), throwsA(isA<StateError>()));
      await close;
    });

    test(
      'dispose blocks notifications from a pending initialization',
      () async {
        final delayedRepository = _DelayedDraftRepository(repository);
        final controller = DraftController(delayedRepository);
        var notifications = 0;
        controller.addListener(() => notifications++);

        final initialization = controller.initialize('one');
        await delayedRepository.getDraftStarted;
        controller.dispose();
        delayedRepository.releaseGetDraft();

        await initialization;
        await controller.close();
        expect(notifications, 0);
      },
    );
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

final class _FixedClock implements Clock {
  _FixedClock(this.now);

  @override
  DateTime now;

  @override
  int get utcOffsetMinutes => 480;
}

final class _IdSequence {
  int _value = 0;

  String next() => 'entry-${_value++}';
}

final class _DelayedDraftRepository implements EntryRepository {
  _DelayedDraftRepository(this._delegate);

  final EntryRepository _delegate;
  final _getDraftStarted = Completer<void>();
  final _getDraftRelease = Completer<void>();

  Future<void> get getDraftStarted => _getDraftStarted.future;

  void releaseGetDraft() => _getDraftRelease.complete();

  @override
  Future<void> deleteEntry(String entryId) => _delegate.deleteEntry(entryId);

  @override
  Future<JournalEntry?> getDraft(String profileId) async {
    _getDraftStarted.complete();
    await _getDraftRelease.future;
    return _delegate.getDraft(profileId);
  }

  @override
  Future<List<JournalEntry>> listDay(String profileId, DateTime localDate) =>
      _delegate.listDay(profileId, localDate);

  @override
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  }) => _delegate.listRange(profileIds: profileIds, from: from, to: to);

  @override
  Future<JournalEntry> publishDraft(String profileId) =>
      _delegate.publishDraft(profileId);

  @override
  Future<JournalEntry> saveDraft({
    required String profileId,
    required String text,
  }) => _delegate.saveDraft(profileId: profileId, text: text);

  @override
  Future<void> updateText({required String entryId, required String text}) =>
      _delegate.updateText(entryId: entryId, text: text);
}
