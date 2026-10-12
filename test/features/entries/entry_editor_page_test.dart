import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_editor_page.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';

void main() {
  final entry = JournalEntry(
    id: 'entry-1',
    profileId: 'me',
    text: 'before',
    createdAt: DateTime.utc(2026, 10, 12, 1, 20),
    updatedAt: DateTime.utc(2026, 10, 12, 1, 20),
    localDate: '2026-10-12',
    timezoneOffsetMinutes: 480,
    status: EntryStatus.published,
  );

  testWidgets('edits text while retaining the displayed 09:20 creation time', (
    tester,
  ) async {
    final entries = _Entries();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryEditorPage(
          entry: entry,
          entryRepository: entries,
          mediaRepository: _Media(),
          deletionService: _Deletion(),
        ),
      ),
    );
    expect(find.text('09:20'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('entry-editor-text')), 'after');
    await tester.tap(find.byKey(const Key('entry-editor-save')));
    await tester.pumpAndSettle();
    expect(entries.updated, <String>['entry-1', 'after']);
    expect(entry.createdAt, DateTime.utc(2026, 10, 12, 1, 20));
  });

  testWidgets('only deletes after confirmation', (tester) async {
    final deletion = _Deletion();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryEditorPage(
          entry: entry,
          entryRepository: _Entries(),
          mediaRepository: _Media(),
          deletionService: deletion,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('entry-editor-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletion.deleted, isFalse);
    await tester.tap(find.byKey(const Key('entry-editor-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletion.deleted, isTrue);
  });
}

final class _Entries implements EntryRepository {
  List<String>? updated;
  @override
  Future<Map<String, int>> countByDay(
    String profileId,
    DateTime monthStart,
    DateTime monthEnd,
  ) async => const <String, int>{};
  @override
  Future<void> deleteEntry(String entryId) async {}
  @override
  Future<JournalEntry?> getDraft(String profileId) async => null;
  @override
  Future<List<JournalEntry>> listDay(
    String profileId,
    DateTime localDate,
  ) async => const <JournalEntry>[];
  @override
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  }) async => const <JournalEntry>[];
  @override
  Future<JournalEntry> publishDraft(String profileId) =>
      throw UnimplementedError();
  @override
  Future<JournalEntry> saveDraft({
    required String profileId,
    required String text,
  }) => throw UnimplementedError();
  @override
  Future<void> updateText({
    required String entryId,
    required String text,
  }) async => updated = <String>[entryId, text];
}

final class _Media implements MediaRepository {
  @override
  Future<void> delete(String mediaId) async {}
  @override
  Future<void> insert(MediaItem item) async {}
  @override
  Future<List<MediaItem>> listForEntry(String entryId) async =>
      const <MediaItem>[];
  @override
  Future<void> updateCaption({
    required String mediaId,
    required String? caption,
  }) async {}
}

final class _Deletion implements EntryDeletionService {
  bool deleted = false;
  @override
  Future<void> delete(JournalEntry entry) async => deleted = true;
}
