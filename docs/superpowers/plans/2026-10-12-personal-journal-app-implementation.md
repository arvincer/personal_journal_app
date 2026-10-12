# Personal Journal App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline-first Flutter iPhone journal that separates records by local profile, stores text/images/videos by day, exports AI-readable Markdown ZIPs, and creates verifiable restorable backups.

**Architecture:** Use a feature-oriented Flutter application with built-in `ChangeNotifier` controllers, a SQLite repository as the source of truth, and an application-private file store for media. Export, backup, and restore are isolated services; platform adapters wrap the iOS share sheet, image picker, file picker, and video thumbnail generation so core logic remains unit-testable on Windows.

**Tech Stack:** Flutter stable, Dart 3, Material 3, `sqflite`, `sqflite_common_ffi`, `path_provider`, `path`, `image_picker`, `file_picker`, `video_thumbnail`, `archive`, `crypto`, `share_plus`, `uuid`, `intl`, Flutter test, GitHub Actions macOS runner.

---

## File map

```text
lib/
├── main.dart                         # dependency composition and app startup
├── app/
│   ├── journal_app.dart              # MaterialApp and theme
│   └── app_shell.dart                # bottom navigation and active profile header
├── core/
│   ├── database/app_database.dart    # schema, migrations, transactions
│   ├── files/app_file_store.dart     # private media/temp paths and atomic moves
│   ├── files/checksum_service.dart   # SHA-256 calculation
│   ├── files/zip_service.dart        # safe ZIP creation/extraction
│   ├── platform/media_picker.dart    # image/video selection adapter
│   ├── platform/share_adapter.dart   # iOS share sheet adapter
│   └── time/clock.dart               # injectable time source
├── features/
│   ├── profiles/
│   │   ├── profile.dart
│   │   ├── profile_repository.dart
│   │   ├── profile_controller.dart
│   │   └── profile_switcher.dart
│   ├── entries/
│   │   ├── entry.dart
│   │   ├── media_item.dart
│   │   ├── entry_repository.dart
│   │   ├── draft_controller.dart
│   │   ├── media_import_service.dart
│   │   ├── today_page.dart
│   │   └── entry_editor_page.dart
│   ├── calendar/calendar_page.dart
│   ├── export/
│   │   ├── export_models.dart
│   │   ├── markdown_renderer.dart
│   │   ├── analysis_export_service.dart
│   │   └── export_page.dart
│   ├── backup/
│   │   ├── backup_manifest.dart
│   │   ├── backup_service.dart
│   │   ├── restore_service.dart
│   │   └── restore_preview.dart
│   └── settings/
│       ├── settings_repository.dart
│       ├── storage_stats_service.dart
│       └── settings_page.dart
test/                                  # mirrors lib/ responsibilities
integration_test/                      # end-to-end happy paths and restore
.github/workflows/ios-build.yml        # unsigned iOS artifact build
docs/side-loading-windows.md            # weekly refresh instructions
```

## Task 1: Bootstrap the Flutter project and test harness

**Files:**
- Create: Flutter-generated project files under repository root
- Modify: `pubspec.yaml`
- Modify: `analysis_options.yaml`
- Create: `test/smoke_test.dart`

- [ ] **Step 1: Verify or install Flutter stable on Windows**

Run:

```powershell
flutter --version
flutter doctor -v
```

Expected: Flutter stable with Dart 3 is available. If `flutter` is not found, install the official stable SDK, add its `bin` directory to the user PATH, reopen the terminal, and rerun both commands before continuing.

- [ ] **Step 2: Generate the application without replacing the existing docs**

Run from the repository root:

```powershell
flutter create --platforms=ios,android --org app.personaljournal --project-name personal_journal_app .
```

Expected: `lib/main.dart`, `ios/`, `android/`, `test/`, and `pubspec.yaml` are created; `docs/` remains unchanged.

- [ ] **Step 3: Add runtime and test dependencies**

Run:

```powershell
flutter pub add sqflite path_provider path image_picker file_picker video_thumbnail archive crypto share_plus uuid intl
flutter pub add --dev sqflite_common_ffi integration_test
```

Expected: dependency resolution succeeds and `pubspec.lock` is created.

- [ ] **Step 4: Replace the generated smoke test**

Create `test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/app/journal_app.dart';

void main() {
  testWidgets('app starts on today page', (tester) async {
    await tester.pumpWidget(const JournalApp.bootstrapForTest());
    expect(find.text('今天'), findsWidgets);
  });
}
```

Create the minimal `lib/app/journal_app.dart`:

```dart
import 'package:flutter/material.dart';

class JournalApp extends StatelessWidget {
  const JournalApp({super.key});
  const JournalApp.bootstrapForTest({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const Scaffold(body: Center(child: Text('今天'))),
    );
  }
}
```

- [ ] **Step 5: Run formatting, analysis, and the smoke test**

Run:

```powershell
dart format lib test
flutter analyze
flutter test test/smoke_test.dart
```

Expected: analyzer reports no issues and the test passes.

- [ ] **Step 6: Commit the bootstrap**

```powershell
git add pubspec.yaml pubspec.lock analysis_options.yaml lib test ios android
git commit -m "chore: bootstrap Flutter journal app"
```

## Task 2: Add domain models and SQLite schema

**Files:**
- Create: `lib/features/profiles/profile.dart`
- Create: `lib/features/entries/entry.dart`
- Create: `lib/features/entries/media_item.dart`
- Create: `lib/core/database/app_database.dart`
- Test: `test/core/database/app_database_test.dart`

- [ ] **Step 1: Write a failing database schema test**

Create `test/core/database/app_database_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates profiles, entries, media and settings tables', () async {
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = rows.map((row) => row['name']).toSet();
    expect(names, containsAll({'profiles', 'entries', 'media', 'settings'}));
    await db.close();
  });
}
```

- [ ] **Step 2: Run the test and verify the missing implementation failure**

Run:

```powershell
flutter test test/core/database/app_database_test.dart
```

Expected: FAIL because `AppDatabase` does not exist.

- [ ] **Step 3: Implement immutable domain records**

Create the three model files with `Profile`, `JournalEntry`, and `MediaItem` classes. Each class must expose all fields from the approved specification, a constructor with required IDs and timestamps, `toMap()`, and `fromMap()` methods. Store booleans as SQLite integers, dates as UTC ISO-8601 strings, and preserve `localDate` as `YYYY-MM-DD` text.

The `JournalEntry` status enum must be:

```dart
enum EntryStatus { draft, published }
```

The media type enum must be:

```dart
enum MediaType { image, video }
```

- [ ] **Step 4: Implement schema version 1**

Create `lib/core/database/app_database.dart` with an injectable `DatabaseFactory`, `open()`, and these constraints:

```sql
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_default INTEGER NOT NULL CHECK (is_default IN (0, 1)),
  is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1))
);

CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  text TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  local_date TEXT NOT NULL,
  timezone_offset_minutes INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'published'))
);

CREATE INDEX entries_profile_date_idx
ON entries(profile_id, local_date, created_at);

CREATE TABLE media (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('image', 'video')),
  relative_path TEXT NOT NULL UNIQUE,
  thumbnail_path TEXT,
  original_filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  caption TEXT,
  checksum_sha256 TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

Enable foreign keys with `PRAGMA foreign_keys = ON` in `onConfigure` and set database version to `1`.

- [ ] **Step 5: Run the database test**

Run:

```powershell
flutter test test/core/database/app_database_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the domain and schema**

```powershell
git add lib/core/database lib/features/profiles/profile.dart lib/features/entries test/core/database
git commit -m "feat: add journal domain schema"
```

## Task 3: Implement local profiles and active-profile persistence

**Files:**
- Create: `lib/features/profiles/profile_repository.dart`
- Create: `lib/features/profiles/profile_controller.dart`
- Test: `test/features/profiles/profile_repository_test.dart`
- Test: `test/features/profiles/profile_controller_test.dart`

- [ ] **Step 1: Write failing repository tests**

Create three tests with these exact fixtures and assertions:

- Open an in-memory database, call `ensureDefaultProfile()` twice, and assert `listActive()` contains exactly one profile named `我的日志` with `isDefault == true`.
- Create a profile and one published entry, call `archive(profile.id)`, assert the profile is absent from `listActive()`, then query `entries` directly and assert its entry remains.
- Create `孩子`, call `writeActiveProfileId(child.id)`, construct a new `ProfileController`, call `initialize()`, and assert `controller.active!.id == child.id`.

- [ ] **Step 2: Run tests and verify failures**

Run:

```powershell
flutter test test/features/profiles
```

Expected: FAIL because repository and controller do not exist.

- [ ] **Step 3: Implement `ProfileRepository`**

Required public interface:

```dart
abstract interface class ProfileRepository {
  Future<Profile> ensureDefaultProfile();
  Future<List<Profile>> listActive();
  Future<Profile> create({required String name});
  Future<void> rename({required String id, required String name});
  Future<void> archive(String id);
  Future<String?> readActiveProfileId();
  Future<void> writeActiveProfileId(String id);
}
```

Implement `SqliteProfileRepository` using `profiles` and `settings`. Use the settings key `active_profile_id`. `ensureDefaultProfile()` runs in a transaction and creates exactly one profile named `我的日志` when none exists.

- [ ] **Step 4: Implement `ProfileController`**

`ProfileController extends ChangeNotifier` and exposes `profiles`, `active`, `loading`, `initialize()`, `createAndSelect(name)`, `select(id)`, `rename(id, name)`, and `archive(id)`. Archiving the active profile selects the default active profile in the same controller operation.

- [ ] **Step 5: Run tests and commit**

```powershell
flutter test test/features/profiles
git add lib/features/profiles test/features/profiles
git commit -m "feat: add local profile switching"
```

Expected: all profile tests pass.

## Task 4: Implement drafts, published entries, and date queries

**Files:**
- Create: `lib/core/time/clock.dart`
- Create: `lib/features/entries/entry_repository.dart`
- Create: `lib/features/entries/draft_controller.dart`
- Test: `test/features/entries/entry_repository_test.dart`
- Test: `test/features/entries/draft_controller_test.dart`

- [ ] **Step 1: Write failing entry tests**

Tests must prove:

- Save `我的草稿` under profile A and `孩子草稿` under profile B; assert `getDraft(A).text` and `getDraft(B).text` return only their own text.
- Use a fixed local time of `2026-10-12 23:30:00 +08:00`, publish a draft, and assert `localDate == '2026-10-12'` and `timezoneOffsetMinutes == 480`.
- Insert three published entries on one date and assert `listDay()` returns their IDs in descending `createdAt` order.
- Save a blank draft with no media and assert `publishDraft()` throws `StateError`.

- [ ] **Step 2: Run and confirm failures**

```powershell
flutter test test/features/entries
```

Expected: FAIL because entry repository is missing.

- [ ] **Step 3: Implement the clock and repository**

Use this clock boundary:

```dart
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}
```

`EntryRepository` must implement `getDraft(profileId)`, `saveDraft(profileId, text)`, `publishDraft(profileId)`, `listDay(profileId, localDate)`, `listRange(profileIds, from, to)`, `updateText(entryId, text)`, and `deleteEntry(entryId)`. Publishing calculates and stores local date plus `timeZoneOffset.inMinutes` once.

- [ ] **Step 4: Implement debounced draft persistence**

`DraftController` owns a `TextEditingController`, loads one draft per active profile, and writes after 400 ms of inactivity. It must flush immediately before profile switching or disposal.

- [ ] **Step 5: Run tests and commit**

```powershell
flutter test test/features/entries
git add lib/core/time lib/features/entries test/features/entries
git commit -m "feat: persist profile-scoped journal drafts"
```

Expected: all entry tests pass.

## Task 5: Build the private file store and transactional media import

**Files:**
- Create: `lib/core/files/app_file_store.dart`
- Create: `lib/core/files/checksum_service.dart`
- Create: `lib/core/platform/media_picker.dart`
- Create: `lib/features/entries/media_import_service.dart`
- Test: `test/core/files/app_file_store_test.dart`
- Test: `test/features/entries/media_import_service_test.dart`

- [ ] **Step 1: Write failing file and rollback tests**

Cover these fixtures and assertions:

- Write `image bytes` to a temporary `.jpg`, stage and commit it with media ID `m1`, and assert the returned relative path is `media/images/m1.jpg` and the file bytes match.
- Hash UTF-8 bytes for `abc` and assert the result equals `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
- Inject a repository that throws during media insertion; assert the staging directory and intended final path contain no imported file afterward.
- Import a fake `.mp4` through a thumbnail adapter that writes `thumb bytes`; assert the saved `MediaItem.thumbnailPath` resolves to an existing file.

- [ ] **Step 2: Implement `AppFileStore` and checksum service**

Use `getApplicationSupportDirectory()` for permanent files and `getTemporaryDirectory()` for staging/export. Expose:

```dart
Future<File> stageCopy(String sourcePath);
Future<String> commitImage(File staged, String mediaId, String extension);
Future<String> commitVideo(File staged, String mediaId, String extension);
Future<String> commitThumbnail(File staged, String mediaId);
Future<void> deleteRelative(String relativePath);
Future<File> resolve(String relativePath);
```

Reject paths containing `..` or resolving outside the application-support root.

- [ ] **Step 3: Add platform picker boundaries**

Define `MediaPicker` returning normalized `PickedMedia` records. Implement it with `image_picker.pickMultiImage()` for images and `image_picker.pickVideo(source: ImageSource.gallery)` for one video at a time. Keep selection separate from importing so tests use fakes.

- [ ] **Step 4: Implement transactional import orchestration**

`MediaImportService.import()` stages and hashes the file, generates a video thumbnail through an injected adapter, creates the `MediaItem`, writes it through the repository transaction, and deletes staged/final files on failure. Never store the system photo-library path as the permanent media path.

- [ ] **Step 5: Run tests and commit**

```powershell
flutter test test/core/files test/features/entries/media_import_service_test.dart
git add lib/core/files lib/core/platform lib/features/entries/media_import_service.dart test/core/files test/features/entries/media_import_service_test.dart
git commit -m "feat: import private journal media safely"
```

## Task 6: Build app composition, navigation, and profile switching UI

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app/journal_app.dart`
- Create: `lib/app/app_shell.dart`
- Create: `lib/features/profiles/profile_switcher.dart`
- Test: `test/app/app_shell_test.dart`
- Test: `test/features/profiles/profile_switcher_test.dart`

- [ ] **Step 1: Write failing widget tests**

Verify four navigation destinations (`今天`, `日历`, `导出`, `设置`), default profile name, switching to `孩子`, and creation of a new profile from the switcher.

- [ ] **Step 2: Implement dependency composition**

`main()` must initialize bindings, open `AppDatabase`, create repositories/services/controllers, await `ProfileController.initialize()`, and pass an immutable dependency container to `JournalApp`. Do not use service locators or global mutable singletons.

- [ ] **Step 3: Implement `AppShell`**

Use `NavigationBar` with an `IndexedStack` so page state survives tab changes. The top area of Today and Calendar contains `ProfileSwitcher`; Export receives the current profile as its default scope.

- [ ] **Step 4: Run widget tests and commit**

```powershell
flutter test test/app test/features/profiles/profile_switcher_test.dart
git add lib/main.dart lib/app lib/features/profiles/profile_switcher.dart test/app test/features/profiles/profile_switcher_test.dart
git commit -m "feat: add app shell and profile switcher"
```

## Task 7: Implement Today timeline, composer, edit, and delete

**Files:**
- Create: `lib/features/entries/today_page.dart`
- Create: `lib/features/entries/entry_editor_page.dart`
- Test: `test/features/entries/today_page_test.dart`
- Test: `test/features/entries/entry_editor_page_test.dart`

- [ ] **Step 1: Write failing interaction tests**

Test these user-visible flows with fake repositories and platform adapters:

- Enter `今天完成了产品设计`, advance the fake clock by 400 ms, assert the fake draft repository received the text, tap `保存`, and assert one published timeline card appears.
- Make the fake picker return two JPGs and one MP4 across the image/video actions; assert three attachment previews appear before publishing.
- Open an entry created at `09:20`, change its text, save, and assert the repository update retains the original `createdAt`.
- Tap delete, assert nothing is removed before confirming, confirm the dialog, then assert the entry and its fake media paths are removed.
- Give `我` and `孩子` different timeline fixtures and drafts; switch profile and assert both the timeline text and composer text change to the child fixtures.

- [ ] **Step 2: Implement the permanent composer**

The composer contains a multiline `TextField`, image button, video button, attachment preview strip, and `保存`. Disable `保存` only when text and attachments are both empty. Show system keyboard dictation naturally; do not request microphone permission.

- [ ] **Step 3: Implement the timeline and editor**

Render published entries newest first with timestamp, text excerpt, image grid, and video thumbnail with duration badge. The editor changes text/captions, preserves original `createdAt/localDate`, and uses a confirmation dialog before deletion.

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/features/entries/today_page_test.dart test/features/entries/entry_editor_page_test.dart
git add lib/features/entries/today_page.dart lib/features/entries/entry_editor_page.dart test/features/entries
git commit -m "feat: add daily journal timeline"
```

## Task 8: Implement calendar and historical day browsing

**Files:**
- Create: `lib/features/calendar/calendar_page.dart`
- Modify: `lib/features/entries/entry_repository.dart`
- Test: `test/features/calendar/calendar_page_test.dart`

- [ ] **Step 1: Write failing calendar tests**

Verify that days with records are marked, selecting a date lists only the active profile's entries, month navigation works, and switching profiles refreshes markers.

- [ ] **Step 2: Add monthly aggregate query**

Add `Map<String, int> countByDay(profileId, monthStart, monthEnd)` using `GROUP BY local_date`. Return zero rows as an empty map.

- [ ] **Step 3: Implement calendar UI**

Use Flutter's date primitives and a focused month grid; do not add a calendar package. Display a dot and count on days with entries, and a chronological list below the selected date.

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/features/calendar
git add lib/features/calendar lib/features/entries/entry_repository.dart test/features/calendar
git commit -m "feat: browse journal history by date"
```

## Task 9: Generate portable Markdown and export manifests

**Files:**
- Create: `lib/features/export/export_models.dart`
- Create: `lib/features/export/markdown_renderer.dart`
- Test: `test/features/export/markdown_renderer_test.dart`

- [ ] **Step 1: Write golden-string tests**

Use a fixture containing Chinese text, two images, one video, captions, and special Markdown characters. Assert exact headings, normalized forward-slash paths, image syntax, video thumbnail, duration, and the “原视频未包含在本次导出” marker when originals are excluded.

- [ ] **Step 2: Implement export models**

Define:

```dart
enum ExportRangePreset { lastSevenDays, currentMonth, all, custom }

class AnalysisExportRequest {
  final Set<String> profileIds;
  final DateTime from;
  final DateTime to;
  final bool includeOriginalVideos;
}
```

Define a versioned manifest with format version `1`, app version, export timestamp, selected profiles, date range, entry count, and media count.

- [ ] **Step 3: Implement `MarkdownRenderer`**

Escape headings and link labels, preserve body paragraphs, use relative POSIX paths, order entries oldest first inside each day, and never embed absolute device paths.

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/features/export/markdown_renderer_test.dart
git add lib/features/export/export_models.dart lib/features/export/markdown_renderer.dart test/features/export
git commit -m "feat: render portable journal markdown"
```

## Task 10: Build analysis ZIP export and system sharing

**Files:**
- Create: `lib/core/files/zip_service.dart`
- Create: `lib/core/platform/share_adapter.dart`
- Create: `lib/features/export/analysis_export_service.dart`
- Create: `lib/features/export/export_page.dart`
- Test: `test/features/export/analysis_export_service_test.dart`
- Test: `test/features/export/export_page_test.dart`

- [ ] **Step 1: Write failing package-layout tests**

Export one and multiple profiles, inspect the ZIP entries, and assert exact presence of `README.md`, `manifest.json`, dated Markdown files under `days`, images, thumbnails, and optional videos. Verify multi-profile exports use `profiles/{profileId}/days` and `profiles/{profileId}/media`.

- [ ] **Step 2: Implement safe ZIP creation**

`ZipService.create()` accepts a staging directory and destination path. Reject symlinks and entries outside the staging root. Write the final archive to a temporary name and rename only after successful close.

- [ ] **Step 3: Implement `AnalysisExportService`**

Query the selected profile/date range, generate Markdown per day, copy only referenced media, write the manifest, create the ZIP, and remove staging files in `finally`. Return the completed ZIP path; never invoke UI directly.

- [ ] **Step 4: Implement sharing and export page**

Wrap `Share.shareXFiles([XFile(zipPath)])` in `ShareAdapter`. The page provides presets, profile selection, the original-video toggle, progress, cancel handling, “生成并分享”, and “保存到文件” through the system share sheet.

- [ ] **Step 5: Run tests and commit**

```powershell
flutter test test/features/export
git add lib/core/files/zip_service.dart lib/core/platform/share_adapter.dart lib/features/export test/features/export
git commit -m "feat: export AI-ready journal archives"
```

## Task 11: Create verifiable full backups

**Files:**
- Create: `lib/features/backup/backup_manifest.dart`
- Create: `lib/features/backup/backup_service.dart`
- Test: `test/features/backup/backup_service_test.dart`

- [ ] **Step 1: Write failing backup tests**

Assert that a backup contains `backup.sqlite`, every referenced media file, thumbnails, `manifest.json`, and `checksums.json`; verify each listed SHA-256 against archive bytes.

- [ ] **Step 2: Implement a consistent SQLite snapshot**

Run `PRAGMA wal_checkpoint(FULL)`, use SQLite's backup/copy strategy while writes are paused by the repository coordinator, then immediately resume writes. Do not copy a live WAL database with ordinary file copy while a transaction is active.

- [ ] **Step 3: Implement `BackupService.createFullBackup()`**

Copy the snapshot and all media to staging, create manifest counts, compute checksums, ZIP atomically, and clean temporary files in `finally`. A failed backup must never appear as a successful final ZIP.

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/features/backup/backup_service_test.dart
git add lib/features/backup test/features/backup/backup_service_test.dart
git commit -m "feat: create verifiable full backups"
```

## Task 12: Validate and merge restored backups

**Files:**
- Create: `lib/features/backup/restore_preview.dart`
- Create: `lib/features/backup/restore_service.dart`
- Test: `test/features/backup/restore_service_test.dart`
- Test: `test/features/backup/restore_security_test.dart`

- [ ] **Step 1: Write failing restore tests**

Cover valid restore, repeated restore, same UUID skip, missing media, bad checksum, unsupported schema version, malicious `../` ZIP entry, and injected mid-copy failure. The failure test must assert that neither new database rows nor copied media remain.

- [ ] **Step 2: Implement validation and preview**

Extract only normalized paths under a fresh temporary directory, enforce reasonable expanded-size and entry-count limits, verify manifest version and all checksums, open backup SQLite read-only, and return counts for new, duplicate, missing, and damaged objects.

- [ ] **Step 3: Implement atomic merge**

Stage all new files first. In one local database transaction, insert profiles, entries, and media with `INSERT OR IGNORE`; track newly copied paths. On any failure, roll back the transaction and delete tracked files. Existing UUIDs are never overwritten.

- [ ] **Step 4: Add restore UI to Settings**

Use `file_picker` for ZIP selection. Show the preview counts and require explicit confirmation. Present a final report and refresh active profile/timeline state after success.

- [ ] **Step 5: Run tests and commit**

```powershell
flutter test test/features/backup/restore_service_test.dart test/features/backup/restore_security_test.dart
git add lib/features/backup lib/features/settings test/features/backup
git commit -m "feat: restore journal backups safely"
```

## Task 13: Finish settings, storage statistics, and side-load reminders

**Files:**
- Create: `lib/features/settings/settings_repository.dart`
- Create: `lib/features/settings/storage_stats_service.dart`
- Create: `lib/features/settings/settings_page.dart`
- Test: `test/features/settings/settings_page_test.dart`

- [ ] **Step 1: Write failing settings tests**

Verify storage categories, persisted original-video preference, manual last-refresh date, estimated remaining days, warning shown at two days or less, and backup reminder action.

- [ ] **Step 2: Implement settings persistence and storage scan**

Use settings keys `export_include_original_videos` and `last_sideload_refresh_date`. Recursively total only known application directories and report database, images, videos, thumbnails, and temporary bytes separately.

- [ ] **Step 3: Implement settings page**

Provide profile management, storage display, export default, create backup, restore backup, and a side-load card. Label the remaining-day value as an estimate based on the user-confirmed refresh date; do not claim to inspect Apple's real provisioning profile.

- [ ] **Step 4: Run tests and commit**

```powershell
flutter test test/features/settings
git add lib/features/settings test/features/settings
git commit -m "feat: add storage and sideload settings"
```

## Task 14: Configure iOS permissions and unsigned CI artifact

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`
- Modify: `android/app/build.gradle.kts`
- Create: `.github/workflows/ios-build.yml`
- Create: `docs/side-loading-windows.md`

- [ ] **Step 1: Set the permanent application identifiers**

Set iOS `PRODUCT_BUNDLE_IDENTIFIER` to `app.personaljournal.mobile` for Runner and test targets. Set Android `namespace` and `applicationId` to the same reverse-domain identifier. Never change these identifiers after installing the first data-bearing build.

- [ ] **Step 2: Add only required iOS privacy text**

Add to `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>选择要保存到个人日志中的图片和视频。</string>
```

Do not add microphone, location, contacts, tracking, push, or iCloud entitlements.

- [ ] **Step 3: Add macOS CI for an unsigned device build**

Create `.github/workflows/ios-build.yml` that checks out code, installs Flutter stable, runs `flutter pub get`, `flutter analyze`, `flutter test`, builds with `flutter build ios --release --no-codesign`, packages `build/ios/iphoneos/Runner.app` as `Payload/Runner.app` inside `personal-journal-unsigned.ipa`, and uploads the IPA artifact. The workflow must never store an Apple password or signing certificate.

- [ ] **Step 4: Document weekly Windows installation**

`docs/side-loading-windows.md` must explain: enable Developer Mode, download the CI artifact, use a dedicated Apple account with the chosen local side-load tool, keep Bundle ID unchanged, refresh within seven days, never uninstall before backup, and verify existing entries after every refresh.

- [ ] **Step 5: Validate configuration and commit**

Run:

```powershell
flutter analyze
flutter test
```

Expected: all tests pass. Then commit:

```powershell
git add ios android .github docs/side-loading-windows.md
git commit -m "build: add private iOS sideload pipeline"
```

## Task 15: Add end-to-end acceptance coverage and release checklist

**Files:**
- Create: `integration_test/journal_flow_test.dart`
- Create: `integration_test/backup_restore_flow_test.dart`
- Create: `docs/release-checklist.md`
- Modify: `README.md`

- [ ] **Step 1: Add the primary journal integration test**

The test creates `我的日志` and `孩子`, records text and fixture media for each, switches profiles, verifies isolation, browses calendar history, edits one entry, and exports an analysis package.

- [ ] **Step 2: Add backup/restore integration test**

Create a full backup, start with a fresh test database/files root, restore it, compare profile/entry/media counts and checksums, restore the same ZIP again, and assert counts remain unchanged.

- [ ] **Step 3: Write the release checklist**

Include physical-iPhone checks for system dictation, multi-image selection, video import, app kill/relaunch draft recovery, photo-library deletion independence, low-space behavior, WeChat sharing, Files saving, Windows ZIP extraction, Markdown links, backup restore, duplicate restore, airplane mode, and free-signature refresh.

- [ ] **Step 4: Document user operations**

Update `README.md` with product scope, development commands, architecture map, data locations, export formats, backup warning, and side-load link. Explicitly state that uninstalling the iPhone app deletes local data unless a full backup exists.

- [ ] **Step 5: Run the complete verification suite**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

On a macOS runner or Mac, also run:

```bash
flutter test integration_test
flutter build ios --release --no-codesign
```

Expected: formatting clean, analyzer clean, unit/widget tests pass, integration tests pass, and iOS release build succeeds.

- [ ] **Step 6: Commit the acceptance suite**

```powershell
git add integration_test README.md docs/release-checklist.md
git commit -m "test: cover journal backup and export flows"
```

## Final verification gate

- [ ] Run `git status --short` and confirm the working tree contains no unintended files.
- [ ] Run `flutter analyze` and record zero errors.
- [ ] Run `flutter test` and record the passing test count.
- [ ] Download the macOS CI IPA artifact and confirm its Bundle ID is `app.personaljournal.mobile`.
- [ ] Refresh-install the IPA over the previous build and confirm existing local data remains present.
- [ ] Create an analysis ZIP, transfer it through微信文件传输助手, and validate it on Windows.
- [ ] Create a full backup and restore it into a clean test installation before using the app for irreplaceable data.
