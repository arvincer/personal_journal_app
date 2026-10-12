import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry_editor_page.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/today_page.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

void main() {
  testWidgets('debounces text then publishes a timeline card', (tester) async {
    final entries = _Entries();
    final profiles = await _profiles();
    final drafts = DraftController(entries);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          profileController: profiles,
          draftController: drafts,
          entryRepository: entries,
          mediaRepository: _Media(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('today-draft-input')), '产品设计');
    await tester.pump(const Duration(milliseconds: 450));
    expect((await entries.getDraft('me'))!.text, '产品设计');

    await tester.tap(find.byKey(const Key('today-save')));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('产品设计'), findsWidgets);
    await drafts.close();
    await profiles.close();
  });

  testWidgets('switching profile replaces draft and timeline', (tester) async {
    final entries = _Entries()
      ..seedPublished('me', '我的记录')
      ..seedPublished('child', '孩子记录')
      ..seedDraft('child', '孩子草稿');
    final profiles = await _profiles();
    final drafts = DraftController(entries);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          profileController: profiles,
          draftController: drafts,
          entryRepository: entries,
          mediaRepository: _Media(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的记录'), findsOneWidget);

    await profiles.select('child');
    await tester.pumpAndSettle();
    expect(find.text('孩子记录'), findsOneWidget);
    expect(find.text('孩子草稿'), findsOneWidget);
    await drafts.close();
    await profiles.close();
  });

  testWidgets('adds two images and one video to the draft preview strip', (
    tester,
  ) async {
    final entries = _Entries();
    final profiles = await _profiles();
    final drafts = DraftController(entries);
    final media = _Media();
    final importer = _Importer(media);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          profileController: profiles,
          draftController: drafts,
          entryRepository: entries,
          mediaRepository: media,
          mediaPicker: _Picker(),
          mediaImporter: importer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('today-add-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('today-add-video')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media-preview-m1')), findsOneWidget);
    expect(find.byKey(const Key('media-preview-m2')), findsOneWidget);
    expect(find.byKey(const Key('media-preview-m3')), findsOneWidget);
    expect(importer.entryIds.toSet(), hasLength(1));
    await drafts.close();
    await profiles.close();
  });

  testWidgets('refreshes the timeline after editing an entry', (tester) async {
    final entries = _Entries()..seedPublished('me', 'Before edit');
    final profiles = await _profiles();
    final drafts = DraftController(entries);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          profileController: profiles,
          draftController: drafts,
          entryRepository: entries,
          mediaRepository: _Media(),
          deletionService: _NoopDeletionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Before edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('entry-editor-text')),
      'After edit',
    );
    await tester.tap(find.byKey(const Key('entry-editor-save')));
    await tester.pumpAndSettle();

    expect(find.text('After edit'), findsOneWidget);
    expect(find.text('Before edit'), findsNothing);
    await drafts.close();
    await profiles.close();
  });
}

Future<ProfileController> _profiles() async {
  final controller = ProfileController(_Profiles());
  await controller.initialize();
  return controller;
}

final class _Entries implements EntryRepository {
  final Map<String, JournalEntry> _drafts = <String, JournalEntry>{};
  final List<JournalEntry> _published = <JournalEntry>[];
  int _next = 1;

  @override
  Future<Map<String, int>> countByDay(
    String profileId,
    DateTime monthStart,
    DateTime monthEnd,
  ) async => <String, int>{
    for (final entry in _published.where(
      (entry) => entry.profileId == profileId,
    ))
      entry.localDate: _published
          .where(
            (candidate) =>
                candidate.profileId == profileId &&
                candidate.localDate == entry.localDate,
          )
          .length,
  };

  void seedDraft(String profileId, String text) => _drafts[profileId] = _entry(
    id: 'draft-$profileId',
    profileId: profileId,
    text: text,
    status: EntryStatus.draft,
  );
  void seedPublished(String profileId, String text) => _published.add(
    _entry(
      id: 'seed-${_next++}',
      profileId: profileId,
      text: text,
      status: EntryStatus.published,
    ),
  );
  JournalEntry _entry({
    required String id,
    required String profileId,
    required String text,
    required EntryStatus status,
  }) => JournalEntry(
    id: id,
    profileId: profileId,
    text: text,
    createdAt: DateTime.utc(2026, 10, 12, 9, 20),
    updatedAt: DateTime.utc(2026, 10, 12, 9, 20),
    localDate: '2026-10-12',
    timezoneOffsetMinutes: 480,
    status: status,
  );

  @override
  Future<void> deleteEntry(String entryId) async =>
      _published.removeWhere((entry) => entry.id == entryId);
  @override
  Future<JournalEntry?> getDraft(String profileId) async => _drafts[profileId];
  @override
  Future<List<JournalEntry>> listDay(
    String profileId,
    DateTime localDate,
  ) async => _published
      .where((entry) => entry.profileId == profileId)
      .toList()
      .reversed
      .toList();
  @override
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  }) async => _published;
  @override
  Future<JournalEntry> publishDraft(String profileId) async {
    final draft = _drafts.remove(profileId)!;
    final published = _entry(
      id: 'entry-${_next++}',
      profileId: profileId,
      text: draft.text,
      status: EntryStatus.published,
    );
    _published.add(published);
    return published;
  }

  @override
  Future<JournalEntry> saveDraft({
    required String profileId,
    required String text,
  }) async => _drafts[profileId] = _entry(
    id: _drafts[profileId]?.id ?? 'draft-${_next++}',
    profileId: profileId,
    text: text,
    status: EntryStatus.draft,
  );
  @override
  Future<void> updateText({
    required String entryId,
    required String text,
  }) async {
    final index = _published.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return;
    final entry = _published[index];
    _published[index] = JournalEntry(
      id: entry.id,
      profileId: entry.profileId,
      text: text,
      createdAt: entry.createdAt,
      updatedAt: DateTime.utc(2026, 10, 12, 10),
      localDate: entry.localDate,
      timezoneOffsetMinutes: entry.timezoneOffsetMinutes,
      status: entry.status,
    );
  }
}

final class _NoopDeletionService implements EntryDeletionService {
  @override
  Future<void> delete(JournalEntry entry) async {}
}

final class _Media implements MediaRepository {
  final List<MediaItem> items = <MediaItem>[];
  @override
  Future<void> delete(String mediaId) async {}
  @override
  Future<void> insert(MediaItem item) async => items.add(item);
  @override
  Future<List<MediaItem>> listForEntry(String entryId) async =>
      items.where((item) => item.entryId == entryId).toList();
  @override
  Future<void> updateCaption({
    required String mediaId,
    required String? caption,
  }) async {}
}

final class _Picker implements MediaPicker {
  @override
  Future<List<PickedMedia>> pickImages() async => <PickedMedia>[
    PickedMedia.image('/one.jpg'),
    PickedMedia.image('/two.jpg'),
  ];
  @override
  Future<PickedMedia?> pickVideo() async => PickedMedia.video('/three.mp4');
}

final class _Importer implements MediaImporter {
  _Importer(this.repository);
  final _Media repository;
  final List<String> entryIds = <String>[];
  @override
  Future<MediaItem> importMedia({
    required String entryId,
    required PickedMedia media,
  }) async {
    entryIds.add(entryId);
    final id = 'm${entryIds.length}';
    final item = MediaItem(
      id: id,
      entryId: entryId,
      type: media.type == PickedMediaType.image
          ? MediaType.image
          : MediaType.video,
      relativePath: 'media/$id',
      thumbnailPath: null,
      originalFilename: media.originalFilename,
      mimeType: '',
      fileSize: 0,
      width: null,
      height: null,
      durationMilliseconds: null,
      caption: null,
      checksumSha256: '',
      createdAt: DateTime.utc(2026),
    );
    await repository.insert(item);
    return item;
  }
}

final class _Profiles implements ProfileRepository {
  final List<Profile> _items = <Profile>[
    _profile('me', '我', true),
    _profile('child', '孩子', false),
  ];
  String? active;
  @override
  Future<void> archive(String id) async {}
  @override
  Future<Profile> create({required String name}) async =>
      throw UnimplementedError();
  @override
  Future<Profile> ensureDefaultProfile() async => _items.first;
  @override
  Future<List<Profile>> listActive() async => _items;
  @override
  Future<String?> readActiveProfileId() async => active;
  @override
  Future<void> rename({required String id, required String name}) async {}
  @override
  Future<void> writeActiveProfileId(String id) async => active = id;
}

Profile _profile(String id, String name, bool isDefault) => Profile(
  id: id,
  name: name,
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: isDefault,
  isArchived: false,
);
