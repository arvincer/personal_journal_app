import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:personal_journal_app/features/settings/settings_page.dart';
import 'package:personal_journal_app/features/settings/settings_repository.dart';
import 'package:personal_journal_app/features/settings/storage_stats_service.dart';

void main() {
  testWidgets('previews and confirms a selected backup before restoring', (
    tester,
  ) async {
    final restorer = _FakeRestorer();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            restorer: restorer,
            backupFilePicker: () async => 'backup.zip',
            onRestored: () async => refreshes++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('从完整备份恢复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(restorer.previewedPath, 'backup.zip');
    expect(find.textContaining('将新增 1 个用户'), findsOneWidget);
    expect(restorer.restoredPath, isNull);

    await tester.tap(find.byKey(const Key('confirm-restore')));
    await tester.pumpAndSettle();
    expect(restorer.restoredPath, 'backup.zip');
    expect(refreshes, 1);
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });

  testWidgets('shows storage, persists defaults, and warns at two days', (
    tester,
  ) async {
    final settings = _FakeSettingsRepository(
      refreshDate: DateTime(2026, 10, 10),
    );
    var backups = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            restorer: _FakeRestorer(),
            backupFilePicker: () async => null,
            onRestored: () async {},
            settingsRepository: settings,
            storageStatsLoader: _FakeStorageStatsLoader(),
            createBackup: () async => backups++,
            todayProvider: () => DateTime(2026, 10, 15),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('数据库 10 B'), findsOneWidget);
    expect(find.textContaining('预计剩余 2 天'), findsOneWidget);
    expect(find.text('建议立即备份，并尽快刷新侧载。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('default-original-videos')));
    await tester.pump();
    expect(settings.includeOriginalVideos, isTrue);

    await tester.tap(find.byKey(const Key('create-full-backup')));
    await tester.pumpAndSettle();
    expect(backups, 1);

    await tester.tap(find.byKey(const Key('confirm-sideload-refresh')));
    await tester.pump();
    expect(settings.refreshDate, DateTime(2026, 10, 15));
    expect(find.textContaining('预计剩余 7 天'), findsOneWidget);
  });
}

final class _FakeRestorer implements BackupRestorer {
  String? previewedPath;
  String? restoredPath;

  @override
  Future<RestorePreview> preview(String archivePath) async {
    previewedPath = archivePath;
    return const RestorePreview(
      newProfiles: 1,
      duplicateProfiles: 0,
      newEntries: 2,
      duplicateEntries: 0,
      newMedia: 3,
      duplicateMedia: 0,
      missingFiles: 0,
      damagedFiles: 0,
    );
  }

  @override
  Future<RestoreReport> restore(String archivePath) async {
    restoredPath = archivePath;
    return const RestoreReport(
      insertedProfiles: 1,
      insertedEntries: 2,
      insertedMedia: 3,
    );
  }
}

final class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.refreshDate});

  bool includeOriginalVideos = false;
  DateTime? refreshDate;

  @override
  Future<bool> readIncludeOriginalVideos() async => includeOriginalVideos;

  @override
  Future<DateTime?> readLastSideloadRefreshDate() async => refreshDate;

  @override
  Future<void> writeIncludeOriginalVideos(bool value) async {
    includeOriginalVideos = value;
  }

  @override
  Future<void> writeLastSideloadRefreshDate(DateTime value) async {
    refreshDate = value;
  }
}

final class _FakeStorageStatsLoader implements StorageStatsLoader {
  @override
  Future<StorageStats> scan() async => const StorageStats(
    databaseBytes: 10,
    imageBytes: 20,
    videoBytes: 30,
    thumbnailBytes: 5,
    temporaryBytes: 7,
  );
}
