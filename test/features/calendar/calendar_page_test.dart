import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/calendar/calendar_page.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

void main() {
  testWidgets(
    'marks dates, lists only the active profile, and refreshes on switch',
    (tester) async {
      final controller = await _controller();
      final repository = _Entries(<JournalEntry>[
        _entry('a', 'one', 'one entry', '2026-10-12'),
        _entry('b', 'one', 'another one entry', '2026-10-12'),
        _entry('c', 'two', 'two entry', '2026-10-12'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarPage(
            profileController: controller,
            entryRepository: repository,
            initialMonth: DateTime(2026, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.countByDayCalls, 1);

      expect(
        find.byKey(const Key('calendar-count-2026-10-12')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-count-2026-10-12')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('calendar-day-2026-10-12')));
      await tester.pumpAndSettle();
      expect(repository.countByDayCalls, 1);
      expect(find.text('one entry'), findsOneWidget);
      expect(find.text('another one entry'), findsOneWidget);
      expect(find.text('two entry'), findsNothing);

      await controller.select('two');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('calendar-count-2026-10-12')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('two entry'), findsOneWidget);
      expect(find.text('one entry'), findsNothing);
    },
  );

  testWidgets('navigates across a year boundary and renders empty months', (
    tester,
  ) async {
    final controller = await _controller();
    final repository = _Entries(const <JournalEntry>[]);
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarPage(
          profileController: controller,
          entryRepository: repository,
          initialMonth: DateTime(2026, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.countByDayCalls, 1);
    expect(find.text('2026年1月'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();
    expect(repository.countByDayCalls, 2);
    expect(find.text('2025年12月'), findsOneWidget);
    expect(find.byKey(const Key('calendar-count-2025-12-01')), findsNothing);
  });

  testWidgets('keeps pending month markers when another day is selected', (
    tester,
  ) async {
    final controller = await _controller();
    final pendingCounts = Completer<Map<String, int>>();
    final repository = _Entries(
      const <JournalEntry>[],
      countCompleter: pendingCounts,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarPage(
          profileController: controller,
          entryRepository: repository,
          initialMonth: DateTime(2026, 10),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('calendar-day-2026-10-12')));
    await tester.pump();
    pendingCounts.complete(const <String, int>{'2026-10-12': 1});
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('calendar-count-2026-10-12')), findsOneWidget);
  });
}

Future<ProfileController> _controller() async {
  final controller = ProfileController(_Profiles());
  await controller.initialize();
  return controller;
}

class _Profiles implements ProfileRepository {
  final profiles = <Profile>[
    _profile('one', 'One', true),
    _profile('two', 'Two', false),
  ];
  String? active;
  @override
  Future<void> archive(String id) async {}
  @override
  Future<Profile> create({required String name}) async =>
      _profile('new', name, false);
  @override
  Future<Profile> ensureDefaultProfile() async => profiles.first;
  @override
  Future<List<Profile>> listActive() async => profiles;
  @override
  Future<String?> readActiveProfileId() async => active;
  @override
  Future<void> rename({required String id, required String name}) async {}
  @override
  Future<void> writeActiveProfileId(String id) async => active = id;
}

class _Entries implements EntryRepository {
  _Entries(this.entries, {this.countCompleter});
  final List<JournalEntry> entries;
  final Completer<Map<String, int>>? countCompleter;
  int countByDayCalls = 0;
  @override
  Future<Map<String, int>> countByDay(
    String profileId,
    DateTime start,
    DateTime end,
  ) async {
    countByDayCalls++;
    if (countCompleter case final completer?) return completer.future;
    return {
      for (final entry in entries.where(
        (entry) =>
            entry.profileId == profileId &&
            entry.status == EntryStatus.published &&
            entry.localDate.compareTo(_date(start)) >= 0 &&
            entry.localDate.compareTo(_date(end)) <= 0,
      ))
        entry.localDate: entries
            .where(
              (candidate) =>
                  candidate.profileId == profileId &&
                  candidate.localDate == entry.localDate &&
                  candidate.status == EntryStatus.published,
            )
            .length,
    };
  }

  @override
  Future<void> deleteEntry(String entryId) async {}
  @override
  Future<JournalEntry?> getDraft(String profileId) async => null;
  @override
  Future<List<JournalEntry>> listDay(
    String profileId,
    DateTime localDate,
  ) async =>
      entries
          .where(
            (entry) =>
                entry.profileId == profileId &&
                entry.localDate == _date(localDate) &&
                entry.status == EntryStatus.published,
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
  }) async {}
}

JournalEntry _entry(
  String id,
  String profileId,
  String text,
  String localDate,
) => JournalEntry(
  id: id,
  profileId: profileId,
  text: text,
  createdAt: DateTime.utc(2026, 10, 12, id == 'a' ? 9 : 10),
  updatedAt: DateTime.utc(2026, 10, 12),
  localDate: localDate,
  timezoneOffsetMinutes: 480,
  status: EntryStatus.published,
);
Profile _profile(String id, String name, bool isDefault) => Profile(
  id: id,
  name: name,
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: isDefault,
  isArchived: false,
);
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
