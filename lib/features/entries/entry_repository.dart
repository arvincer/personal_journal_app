import 'dart:async';
import 'dart:collection';

import 'package:personal_journal_app/core/time/clock.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

typedef EntryIdProvider = String Function();

abstract interface class EntryRepository {
  Future<JournalEntry?> getDraft(String profileId);
  Future<JournalEntry> saveDraft({
    required String profileId,
    required String text,
  });
  Future<JournalEntry> publishDraft(String profileId);
  Future<List<JournalEntry>> listDay(String profileId, DateTime localDate);
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  });
  Future<void> updateText({required String entryId, required String text});
  Future<void> deleteEntry(String entryId);
}

final class SqliteEntryRepository implements EntryRepository {
  SqliteEntryRepository(
    this._database, {
    Clock? clock,
    EntryIdProvider? idProvider,
  }) : _clock = clock ?? const SystemClock(),
       _idProvider = idProvider ?? const Uuid().v4;

  static final HashMap<Database, Future<void>> _operationTails =
      HashMap<Database, Future<void>>.identity();

  final Database _database;
  final Clock _clock;
  final EntryIdProvider _idProvider;

  @override
  Future<JournalEntry?> getDraft(String profileId) async {
    final rows = await _database.query(
      'entries',
      where: 'profile_id = ? AND status = ?',
      whereArgs: <Object?>[profileId, EntryStatus.draft.name],
      orderBy: 'created_at ASC, id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : JournalEntry.fromMap(rows.single);
  }

  @override
  Future<JournalEntry> saveDraft({
    required String profileId,
    required String text,
  }) {
    return _serialize(() {
      return _database.transaction((transaction) async {
        final drafts = await transaction.query(
          'entries',
          where: 'profile_id = ? AND status = ?',
          whereArgs: <Object?>[profileId, EntryStatus.draft.name],
          orderBy: 'created_at ASC, id ASC',
          limit: 1,
        );
        final localNow = _clock.now;
        final now = _utcAt(localNow);
        if (drafts.isNotEmpty) {
          final existing = JournalEntry.fromMap(drafts.single);
          await transaction.update(
            'entries',
            <String, Object?>{
              'text': text,
              'updated_at': now.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: <Object?>[existing.id],
          );
          return JournalEntry(
            id: existing.id,
            profileId: existing.profileId,
            text: text,
            createdAt: existing.createdAt,
            updatedAt: now,
            localDate: existing.localDate,
            timezoneOffsetMinutes: existing.timezoneOffsetMinutes,
            status: EntryStatus.draft,
          );
        }

        final draft = JournalEntry(
          id: _idProvider(),
          profileId: profileId,
          text: text,
          createdAt: now,
          updatedAt: now,
          localDate: _localDate(localNow),
          timezoneOffsetMinutes: _clock.utcOffsetMinutes,
          status: EntryStatus.draft,
        );
        await transaction.insert('entries', draft.toMap());
        return draft;
      });
    });
  }

  @override
  Future<JournalEntry> publishDraft(String profileId) {
    return _serialize(() {
      return _database.transaction((transaction) async {
        final rows = await transaction.query(
          'entries',
          where: 'profile_id = ? AND status = ?',
          whereArgs: <Object?>[profileId, EntryStatus.draft.name],
          orderBy: 'created_at ASC, id ASC',
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('No draft exists for profile "$profileId".');
        }
        final draft = JournalEntry.fromMap(rows.single);
        await _validatePublishable(transaction, draft.id, draft.text);
        final localNow = _clock.now;
        final now = _utcAt(localNow);
        final published = JournalEntry(
          id: draft.id,
          profileId: draft.profileId,
          text: draft.text,
          createdAt: now,
          updatedAt: now,
          localDate: _localDate(localNow),
          timezoneOffsetMinutes: _clock.utcOffsetMinutes,
          status: EntryStatus.published,
        );
        await transaction.update(
          'entries',
          published.toMap()
            ..remove('id')
            ..remove('profile_id'),
          where: 'id = ?',
          whereArgs: <Object?>[draft.id],
        );
        return published;
      });
    });
  }

  @override
  Future<List<JournalEntry>> listDay(
    String profileId,
    DateTime localDate,
  ) async {
    final rows = await _database.query(
      'entries',
      where: 'profile_id = ? AND status = ? AND local_date = ?',
      whereArgs: <Object?>[
        profileId,
        EntryStatus.published.name,
        _localDate(localDate),
      ],
      orderBy: 'created_at DESC, id ASC',
    );
    return rows.map(JournalEntry.fromMap).toList(growable: false);
  }

  @override
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  }) async {
    if (profileIds.isEmpty) {
      return const <JournalEntry>[];
    }
    final placeholders = List<String>.filled(profileIds.length, '?').join(', ');
    final rows = await _database.query(
      'entries',
      where:
          'status = ? AND profile_id IN ($placeholders) '
          'AND local_date >= ? AND local_date <= ?',
      whereArgs: <Object?>[
        EntryStatus.published.name,
        ...profileIds,
        _localDate(from),
        _localDate(to),
      ],
      orderBy: 'local_date DESC, created_at DESC, id ASC',
    );
    return rows.map(JournalEntry.fromMap).toList(growable: false);
  }

  @override
  Future<void> updateText({required String entryId, required String text}) {
    return _serialize(() {
      return _database.transaction((transaction) async {
        final rows = await transaction.query(
          'entries',
          where: 'id = ?',
          whereArgs: <Object?>[entryId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Cannot update unknown entry "$entryId".');
        }
        final entry = JournalEntry.fromMap(rows.single);
        if (entry.status == EntryStatus.published) {
          await _validatePublishable(transaction, entryId, text);
        }
        await transaction.update(
          'entries',
          <String, Object?>{
            'text': text,
            'updated_at': _utcAt(_clock.now).toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: <Object?>[entryId],
        );
      });
    });
  }

  @override
  Future<void> deleteEntry(String entryId) {
    return _serialize(() async {
      await _database.delete(
        'entries',
        where: 'id = ?',
        whereArgs: <Object?>[entryId],
      );
    });
  }

  Future<void> _validatePublishable(
    DatabaseExecutor executor,
    String entryId,
    String text,
  ) async {
    if (text.trim().isNotEmpty) {
      return;
    }
    final media = await executor.query(
      'media',
      columns: <String>['id'],
      where: 'entry_id = ?',
      whereArgs: <Object?>[entryId],
      limit: 1,
    );
    if (media.isEmpty) {
      throw StateError('An entry needs text or media before publication.');
    }
  }

  DateTime _utcAt(DateTime localTime) {
    return DateTime.utc(
      localTime.year,
      localTime.month,
      localTime.day,
      localTime.hour,
      localTime.minute,
      localTime.second,
      localTime.millisecond,
      localTime.microsecond,
    ).subtract(Duration(minutes: _clock.utcOffsetMinutes));
  }

  String _localDate(DateTime time) {
    return '${time.year.toString().padLeft(4, '0')}-'
        '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';
  }

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final previous = _operationTails[_database] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = previous.then<void>(
      (_) => release.future,
      onError: (_) => release.future,
    );
    _operationTails[_database] = tail;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed caller must not retain the repository lock.
      }
      return await operation();
    } finally {
      release.complete();
      if (identical(_operationTails[_database], tail)) {
        _operationTails.remove(_database);
      }
    }
  }
}
